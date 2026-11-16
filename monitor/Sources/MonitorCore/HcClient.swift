import Foundation

/// `hc`(herdr-core CLI)를 읽기 전용으로 부른다.
/// `hc ls`에는 사용자의 다른 터미널이 모두 보인다. 그래서 쓰는 명령은 아래 네 개뿐이고, 쓰기 명령은 코드에 두지 않는다.
public enum HcClient {
    public enum HcError: Error, Equatable {
        case notFound
        case forbidden(String)
        case failed(Int32)
        case timedOut
    }

    private static let readOnly: Set<String> = ["ls", "get", "events", "read"]

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

    /// `hc events` 한 줄이 상태 변화인가. 하트비트(`"method":"heartbeat"`)는 아니다.
    public static func isChange(line: String) -> Bool { !line.contains("\"method\":\"heartbeat\"") }

    // MARK: 실행

    public static func list() throws -> [Terminal] { parseLs(try run(["ls"])) }

    public static func statusText(of address: String) -> String? {
        guard !address.hasPrefix("-"), let data = try? run(["get", address]) else { return nil }
        return parseStatusText(data)
    }

    /// 화면과 기록을 글자로 읽는다.
    public static func read(address: String, lines: Int = 40) throws -> String {
        guard !address.hasPrefix("-") else { throw HcError.forbidden(address) }
        return String(decoding: try run(["read", "--lines", String(lines), address]), as: UTF8.self)
    }

    static func makeProcess(_ args: [String]) throws -> Process {
        guard let verb = args.first, readOnly.contains(verb) else { throw HcError.forbidden(args.first ?? "") }
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
