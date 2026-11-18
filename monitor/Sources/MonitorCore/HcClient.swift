import Foundation

/// `hc`(herdr-core CLI)를 부른다. 읽기는 `ls`·`get`·`events`·`read` 네 개다.
/// `hc ls`에는 사용자의 다른 터미널이 모두 보인다. 그래서 쓰기는 `send`(메시지)와 `keys`(숫자 1~9 하나, 객관식 답) 두 개만 `write`로 허용한다.
/// 쓰기는 사용자가 버튼을 누를 때만 부른다. `kill`·`rm`·`run`·`interrupt`·`server`와 `send --force`는 코드에 두지 않는다.
public enum HcClient {
    public enum HcError: Error, Equatable {
        case notFound
        case forbidden(String)
        case failed(Int32)
        case timedOut
    }

    private static let readOnly: Set<String> = ["ls", "get", "events", "read"]
    private static let writes: Set<String> = ["send", "keys"]

    // MARK: 찾기

    /// 메뉴 막대 앱에는 셸의 PATH가 없으므로 흔한 위치를 먼저 본다.
    public static func locate(env: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> String? {
        var candidates: [String] = []
        if let p = env["MMCODE_MONITOR_HC"], !p.isEmpty { candidates.append(p) }
        candidates += ["\(home)/.local/bin/hc", "/opt/homebrew/bin/hc", "/usr/local/bin/hc"]
        candidates += (env["PATH"] ?? "").split(separator: ":").map { "\($0)/hc" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: 해석(순수 함수)

    /// `hc ls` JSON → 터미널 목록. 주소가 없는 항목은 건너뛴다.
    public static func parseLs(_ data: Data) -> [Terminal] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = root["terminals"] as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            guard let address = r["address"] as? String, !address.isEmpty else { return nil }
            let agent = r["agent"] as? String ?? ""
            return Terminal(address: address, harness: Harness(raw: agent), agentRaw: agent, cwd: r["cwd"] as? String ?? "",
                            state: r["state"] as? String ?? "", status: AgentStatus(raw: r["status"] as? String),
                            turn: r["turn"] as? Int ?? 0, location: r["where"] as? String ?? "")
        }
    }

    /// `hc get <주소>` JSON → 상태 문구. 최상위 `title`(에이전트가 터미널 제목으로 보고한 글)을 쓴다. 비어 있으면 nil.
    public static func parseStatusText(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let title = root["title"] as? String, !title.isEmpty else { return nil }
        return title
    }

    /// `hc get <주소>` JSON → `status.kind`(예: `question`, `permission`). 없으면 nil.
    public static func parseStatusKind(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (root["status"] as? [String: Any])?["kind"] as? String
    }

    /// `hc events` 한 줄이 상태 변화인가. 하트비트(`"method":"heartbeat"`)는 아니다.
    public static func isChange(line: String) -> Bool { !line.contains("\"method\":\"heartbeat\"") }

    // MARK: 실행

    public static func list() throws -> [Terminal] { parseLs(try run(["ls"])) }

    /// `hc get` 한 번으로 상태 문구와 status.kind를 읽는다.
    public static func status(of address: String) -> (text: String?, kind: String?) {
        guard !address.hasPrefix("-"), let data = try? run(["get", address]) else { return (nil, nil) }
        return (parseStatusText(data), parseStatusKind(data))
    }

    /// 화면과 기록을 글자로 읽는다.
    public static func read(address: String, lines: Int = 40) throws -> String {
        guard !address.hasPrefix("-") else { throw HcError.forbidden(address) }
        return String(decoding: try run(["read", "--lines", String(lines), address]), as: UTF8.self)
    }

    // MARK: 쓰기

    /// 쓰기 인자 배열. 사용자 글은 셸을 거치지 않고 한 칸으로 들어간다. `--` 뒤에 두어 `-`로 시작하는 글도 옵션이 되지 않는다.
    /// 주소가 `-`로 시작하거나 비면, `keys`가 숫자 1~9 하나가 아니면 거부한다.
    public static func writeArgs(_ verb: String, address: String, _ payload: String) throws -> [String] {
        guard writes.contains(verb) else { throw HcError.forbidden(verb) }
        guard !address.isEmpty, !address.hasPrefix("-") else { throw HcError.forbidden(address) }
        if verb == "keys" {
            guard payload.count == 1, let d = payload.first, ("1"..."9").contains(d) else { throw HcError.forbidden(payload) }
            return [verb, address, payload]
        }
        return [verb, address, "--", payload]
    }

    /// 쓰기 명령을 실행한다. 성공이면 nil, 실패면 이유. 메인 스레드에서 부르지 않는다.
    /// `HC_TERMINAL_ID`를 뺀 환경으로 띄운다. 그래야 받는 세션이 감싸지 않은 사용자 입력으로 받는다.
    public static func write(_ verb: String, address: String, _ payload: String, timeout: TimeInterval) -> String? {
        let p: Process
        do { p = try process(writeArgs(verb, address: address, payload)) }
        catch HcError.notFound { return "hc를 찾지 못했습니다" }
        catch { return "허용하지 않는 명령입니다" }
        p.environment = PhaseClient.environment()
        p.standardError = Pipe()
        do {
            let r = try exec(process: p, timeout: timeout)
            return r.status == 0 ? nil : failReason(out: r.out, err: r.err, status: r.status)
        } catch HcError.timedOut {
            return "응답이 없습니다"
        } catch {
            return "실행하지 못했습니다"
        }
    }

    /// hc의 오류 JSON(`{"error":{"message":…}}`)의 message, 없으면 stderr 첫 줄.
    static func failReason(out: Data, err: Data, status: Int32) -> String {
        for d in [out, err] {
            if let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let m = (o["error"] as? [String: Any])?["message"] as? String { return m }
        }
        let first = String(decoding: err, as: UTF8.self).split(whereSeparator: \.isNewline).first.map(String.init)
        return first ?? "종료 코드 \(status)"
    }

    static func makeProcess(_ args: [String]) throws -> Process {
        guard let verb = args.first, readOnly.contains(verb) else { throw HcError.forbidden(args.first ?? "") }
        return try process(args)
    }

    /// 검사는 부르는 쪽(`makeProcess`, `writeArgs`)이 한다.
    private static func process(_ args: [String]) throws -> Process {
        guard let path = locate() else { throw HcError.notFound }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return p
    }

    static func run(_ args: [String]) throws -> Data { try run(process: makeProcess(args), timeout: 5) }

    /// 시간 안에 끝나지 않으면 이 함수가 띄운 프로세스만 끝내고 `timedOut`을 던진다. hc가 멈춰도 갱신이 멈추지 않게 한다.
    /// ponytail: SIGTERM만 보낸다. 그래도 안 끝나는 프로세스는 계속 기다린다. 그런 경우가 생기면 SIGKILL을 더한다.
    static func run(process p: Process, timeout: TimeInterval) throws -> Data {
        let r = try exec(process: p, timeout: timeout)
        guard r.status == 0 else { throw HcError.failed(r.status) }
        return r.out
    }

    /// `run`과 같지만 종료 코드와 상관없이 출력과 종료 코드를 돌려준다. `p.standardError`가 Pipe면 그것도 읽는다.
    /// ponytail: stdout을 다 읽은 뒤 stderr를 읽는다. stderr가 파이프 한도(64KB)를 넘으면 시간 제한까지 기다린다.
    static func exec(process p: Process, timeout: TimeInterval) throws -> (out: Data, err: Data, status: Int32) {
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let lock = NSLock()
        var late = false
        let stop = DispatchWorkItem { lock.lock(); if p.isRunning { late = true; p.terminate() }; lock.unlock() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
        let data = out.fileHandleForReading.readDataToEndOfFile()  // 대기 전에 읽어야 파이프가 막히지 않는다.
        let err = (p.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        p.waitUntilExit()
        stop.cancel()
        lock.lock(); let timedOut = late; lock.unlock()
        if timedOut { throw HcError.timedOut }
        return (data, err, p.terminationStatus)
    }

    // MARK: 스트림

    /// `hc events --json`을 자식 프로세스로 띄워 줄마다 콜백을 부른다. 콜백은 백그라운드 스레드에서 불린다.
    /// 첫 줄은 전체 터미널 스냅샷, 이후는 변화와 하트비트다. 줄의 내용은 해석하지 않고 `isChange`로만 거른다.
    public final class EventStream {
        private let process: Process
        private let out = Pipe()

        public init() throws {
            process = try HcClient.makeProcess(["events", "--json"])
            process.standardOutput = out
        }

        public func start(onLine: @escaping (String) -> Void, onExit: (() -> Void)? = nil) throws {
            var buffer = Data()
            out.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    h.readabilityHandler = nil
                    onExit?()
                    return
                }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if !line.isEmpty { onLine(line) }
                }
            }
            try process.run()
        }

        deinit { stop() }

        /// 이 객체가 띄운 프로세스만 끝낸다.
        public func stop() {
            out.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
    }
}
