import Foundation

/// 사용자의 답과 지시를 relay의 phase.sh로 기록 파일에 쓴다. 앱이 쓰는 길은 이것 하나다.
/// 하위 명령은 `answer`, `direct` 두 개뿐이다. 다른 하위 명령(move, check 등)은 코드가 거부한다.
/// ponytail: 대상은 늘 프로젝트 폴더(폴더 모드, plan `-`)다. 그래서 답과 지시가 그 프로젝트의 모든 계획에 걸린다.
/// HANDOFF로 보내면 그 계획에만 걸린다. 계획이 여럿인 프로젝트가 생기면 HANDOFF 경로로 바꾼다.
public enum PhaseClient {
    public enum Outcome: Equatable, Sendable {
        /// 종료 코드 0. stdout 마지막 줄(`OK: …`).
        case ok(String)
        /// 종료 코드 1. `REFUSED: ` 뒤의 이유.
        case refused(String)
        /// 종료 코드 2(사용 오류). stderr 첫 줄.
        case usage(String)
        /// 실행하지 못했거나 그 밖의 종료 코드.
        case failed(String)
        /// 시간 안에 끝나지 않았다. 기록은 이미 적혔을 수 있다.
        case noReply
    }

    private static let allowed: Set<String> = ["answer", "direct"]

    // MARK: 찾기

    /// 환경 변수 → 설치된 플러그인 캐시(판 번호가 가장 높은 것) → 디렉터리로 등록한 마켓플레이스.
    /// 프로젝트 안의 사본은 보지 않는다. 남이 만든 저장소의 스크립트를 버튼 하나로 실행하게 되기 때문이다.
    public static func locate(root: String, env: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> String? {
        let tail = "skills/relay/scripts/phase.sh"
        var c: [String] = []
        if let p = env["MMCODE_MONITOR_PHASE"], !p.isEmpty { c.append(p) }
        let cache = "\(home)/.claude/plugins/cache/mmcode/mmcode"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: cache)) ?? []
        c += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(cache)/\($0)/\(tail)" }
        // 디렉터리 원본 마켓플레이스는 설치 위치가 원본 저장소다.
        let known = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/.claude/plugins/known_marketplaces.json"))
        if let obj = known.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
           let loc = (obj["mmcode"] as? [String: Any])?["installLocation"] as? String {
            c.append("\(loc)/plugins/mmcode/\(tail)")
        }
        return c.first { FileManager.default.isReadableFile(atPath: $0) }
    }

    // MARK: 인자

    /// `/bin/bash`에 넘길 인자 배열. 셸 문자열을 만들지 않으므로 사용자가 적은 글은 인자 하나로 그대로 들어간다.
    public static func arguments(phase: String, _ sub: String, root: String, _ rest: [String]) throws -> [String] {
        guard allowed.contains(sub) else { throw HcClient.HcError.forbidden(sub) }
        return [phase, sub, root] + rest
    }

    public static func answerArgs(decision: String, text: String) -> [String] { [decision, "--answer", text, "--by", "user"] }

    /// 메시지는 받을 터미널을 함께 적는다.
    public static func directArgs(_ kind: DirectiveKind, text: String? = nil, terminal: String? = nil) -> [String] {
        [kind.rawValue] + (text.map { ["--text", $0] } ?? []) + (terminal.map { ["--terminal", $0] } ?? [])
    }

    // MARK: 실행

    /// 메인 스레드에서 부르지 않는다. 최대 `timeout`초 기다린다.
    public static func run(phase: String, _ sub: String, root: String, _ rest: [String], timeout: TimeInterval = 10) -> Outcome {
        let args: [String]
        do { args = try arguments(phase: phase, sub, root: root, rest) } catch { return .failed("허용하지 않는 하위 명령: \(sub)") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = args
        p.environment = environment()
        p.standardInput = FileHandle.nullDevice
        p.standardError = Pipe()
        do {
            let r = try HcClient.exec(process: p, timeout: timeout)
            return interpret(status: r.status, out: String(decoding: r.out, as: UTF8.self), err: String(decoding: r.err, as: UTF8.self))
        } catch HcClient.HcError.timedOut {
            return .noReply
        } catch {
            return .failed("실행하지 못했습니다")
        }
    }

    public static func answer(phase: String, root: String, decision: String, text: String) -> Outcome {
        run(phase: phase, "answer", root: root, answerArgs(decision: decision, text: text))
    }

    public static func direct(phase: String, root: String, _ kind: DirectiveKind, text: String? = nil, terminal: String? = nil) -> Outcome {
        run(phase: phase, "direct", root: root, directArgs(kind, text: text, terminal: terminal))
    }

    static func interpret(status: Int32, out: String, err: String) -> Outcome {
        func last(_ s: String) -> String { s.split(whereSeparator: \.isNewline).last.map(String.init) ?? "" }
        func first(_ s: String) -> String { s.split(whereSeparator: \.isNewline).first.map(String.init) ?? "" }
        switch status {
        case 0: return .ok(last(out))
        case 1:
            let l = last(out)
            return .refused(l.hasPrefix("REFUSED: ") ? String(l.dropFirst("REFUSED: ".count)) : l)
        case 2: return .usage(first(err))
        default: return .failed(first(err).isEmpty ? "종료 코드 \(status)" : first(err))
        }
    }

    /// 메뉴 막대 앱에는 셸의 PATH가 없다. phase.sh는 python3와 git이 필요하다.
    /// 행위자 변수는 뺀다. 앱을 띄운 터미널이 지시를 쓴 쪽으로 기록되지 않게 한다.
    static func environment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base.filter { !["HC_TERMINAL_ID", "PHASE_HARNESS", "PHASE_MODEL", "PHASE_EFFORT"].contains($0.key) }
        let extra = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = base["PATH"].map { $0.isEmpty ? extra : extra + ":" + $0 } ?? extra
        return env
    }
}
