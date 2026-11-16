import Foundation
import Testing
@testable import MonitorCore

// 가짜 phase.sh: 받은 인자를 줄마다 적고, 프로젝트 폴더 이름으로 종료 코드를 고른다.
private let fake = #"""
printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
case "$(basename "$2")" in
  refuse) echo "읽는 중"; echo "REFUSED: 이미 답한 결정이다"; exit 1 ;;
  slow) sleep 3 ;;
  usage) echo "알 수 없는 인자: --x" >&2; echo "사용: phase.sh" >&2; exit 2 ;;
  *) echo "준비"; echo "OK: I3 지시 접수 (message)" ;;
esac
"""#

private func tempDir(_ name: String) -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private func fakePhase() -> (dir: URL, phase: String) {
    let d = tempDir("phase")
    let p = d.appendingPathComponent("phase.sh").path
    try! fake.write(toFile: p, atomically: true, encoding: .utf8)
    return (d, p)
}

private func args(_ d: URL) -> [String]? {
    (try? String(contentsOf: d.appendingPathComponent("args.txt"), encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
}

@Test func onlyAnswerAndDirectAllowed() {
    let (d, phase) = fakePhase()
    defer { try? FileManager.default.removeItem(at: d) }
    #expect(throws: HcClient.HcError.forbidden("move")) { try PhaseClient.arguments(phase: phase, "move", root: "/r", []) }
    #expect(PhaseClient.run(phase: phase, "check", root: "/r", []) == .failed("허용하지 않는 하위 명령: check"))
    #expect(args(d) == nil, "거부한 하위 명령은 실행하지 않는다")
}

@Test func userTextStaysOneArgument() {
    let (d, phase) = fakePhase()
    defer { try? FileManager.default.removeItem(at: d) }
    let text = "a b; $(touch x) \"q\""
    #expect(PhaseClient.answer(phase: phase, root: "/w/ok", decision: "D1", text: text) == .ok("OK: I3 지시 접수 (message)"))
    #expect(args(d) == ["answer", "/w/ok", "D1", "--answer", text, "--by", "user"])
    _ = PhaseClient.direct(phase: phase, root: "/w/ok", .message, text: "hi", terminal: "t2")
    #expect(args(d) == ["direct", "/w/ok", "message", "--text", "hi", "--terminal", "t2"])
    _ = PhaseClient.direct(phase: phase, root: "/w/ok", .stopAfter)
    #expect(args(d) == ["direct", "/w/ok", "stop-after"])
}

@Test func exitCodesInterpreted() {
    let (d, phase) = fakePhase()
    defer { try? FileManager.default.removeItem(at: d) }
    #expect(PhaseClient.direct(phase: phase, root: "/w/refuse", .resume) == .refused("이미 답한 결정이다"))
    #expect(PhaseClient.direct(phase: phase, root: "/w/usage", .resume) == .usage("알 수 없는 인자: --x"))
    #expect(PhaseClient.interpret(status: 127, out: "", err: "") == .failed("종료 코드 127"))
    // 시간 초과는 이미 적혔을 수 있다. 실패로 적지 않는다.
    #expect(PhaseClient.run(phase: phase, "direct", root: "/w/slow", ["resume"], timeout: 0.3) == .noReply)
}

@Test func environmentHasToolsAndNoActor() {
    let env = PhaseClient.environment(["PATH": "", "HC_TERMINAL_ID": "t1", "PHASE_MODEL": "m", "HOME": "/h"])
    #expect(env["PATH"]?.contains("/opt/homebrew/bin") == true && env["PATH"]?.hasPrefix("/usr/bin") == true)
    #expect(env["HC_TERMINAL_ID"] == nil && env["PHASE_MODEL"] == nil && env["HOME"] == "/h")
}

@Test func locateOrder() throws {
    let home = tempDir("home"), root = tempDir("proj")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: root) }
    func put(_ path: String) { try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true); FileManager.default.createFile(atPath: path, contents: Data()) }
    let tail = "skills/relay/scripts/phase.sh", cache = home.path + "/.claude/plugins/cache/mmcode/mmcode"
    #expect(PhaseClient.locate(root: root.path, env: [:], home: home.path) == nil)
    put("\(cache)/0.9.0/\(tail)"); put("\(cache)/0.10.0/\(tail)")
    #expect(PhaseClient.locate(root: root.path, env: [:], home: home.path) == "\(cache)/0.10.0/\(tail)", "판 번호는 숫자로 비교한다")
    put(root.path + "/plugins/mmcode/" + tail)
    #expect(PhaseClient.locate(root: root.path, env: [:], home: home.path) == "\(cache)/0.10.0/\(tail)", "프로젝트 안의 사본은 실행하지 않는다")
    put(home.path + "/mine.sh")
    #expect(PhaseClient.locate(root: root.path, env: ["MMCODE_MONITOR_PHASE": home.path + "/mine.sh"], home: home.path) == home.path + "/mine.sh")
}

// MARK: 끝에서 끝

/// 진짜 phase.sh. `MMCODE_TEST_PHASE`가 없으면 이 저장소의 사본을 쓴다.
private let realPhase: String? = {
    let env = ProcessInfo.processInfo.environment["MMCODE_TEST_PHASE"]
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../plugins/mmcode/skills/relay/scripts/phase.sh").standardized.path
    return [env, repo].compactMap { $0 }.first { FileManager.default.isReadableFile(atPath: $0) }
}()

private func sh(_ exe: String, _ a: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe); p.arguments = a
    p.environment = PhaseClient.environment()
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try! p.run(); p.waitUntilExit()
    return p.terminationStatus
}

@Test(.enabled(if: realPhase != nil)) func answerAndDirectRoundTrip() throws {
    let phase = realPhase!, root = tempDir("e2e")
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(sh("/usr/bin/git", ["init", "-q", root.path]) == 0)
    #expect(sh("/bin/bash", [phase, "ask", root.path, "-", "--question", "무엇을 할까요?", "--recommend", "A", "--option", "A", "--option", "B"]) == 0)

    #expect(PhaseClient.answer(phase: phase, root: root.path, decision: "D1", text: "B") == .ok("OK: D1 답 기록"))
    #expect(PhaseClient.answer(phase: phase, root: root.path, decision: "D1", text: "A") == .refused("D1 는 이미 답한 결정이다"))
    #expect(PhaseClient.direct(phase: phase, root: root.path, .message, text: "시험 다시", terminal: "t9") == .ok("OK: I1 지시 접수 (message)"))
    #expect(PhaseClient.direct(phase: phase, root: root.path, .stopAfter) == .ok("OK: I2 지시 접수 (stop-after)"))
    #expect(PhaseClient.direct(phase: phase, root: root.path, .resume) == .ok("OK: I3 지시 접수 (resume, 닫음: I2)"))
    if case .usage = PhaseClient.run(phase: phase, "direct", root: root.path, ["bogus"]) {} else { Issue.record("사용 오류여야 한다") }

    let log = root.appendingPathComponent(".mmcode/events.jsonl")
    let p = try #require(EventLog.read(url: log).plans.first)
    #expect(p.plan == "-")
    #expect(p.decisions.first?.options == ["A", "B"] && p.decisions.first?.recommendation == "A" && p.decisions.first?.answer == "B")
    #expect(p.directives.map(\.id) == ["I1", "I2", "I3"])
    #expect(p.directives[0].kind == .message && p.directives[0].terminal == "t9" && p.directives[0].isOpen)
    #expect(p.directives[1].closed && !p.directives[1].isOpen)
    #expect(p.directives[2].kind == .resume)
    // 앱이 쓴 지시에는 행위자가 없다(앱을 띄운 터미널로 기록되지 않는다).
    let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").filter { $0.contains("directive.received") }
    for l in lines {
        let obj = try JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any]
        #expect((obj?["actor"] as? [String: Any])?.isEmpty == true)
    }
}
