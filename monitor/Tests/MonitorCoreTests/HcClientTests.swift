import Foundation
import Testing
@testable import MonitorCore

// 가짜 자료다. 실제 폴더 이름이나 경로를 쓰지 않는다.
private let lsJSON = """
{"hidden_finished":1,"machines":[{"name":"m","state":"connected"}],"terminals":[
 {"address":"t1","agent":"claude-code","cwd":"/work/alpha","state":"live","status":"working","turn":4,"where":"space-a / tab-1"},
 {"address":"t2","agent":"zsh","cwd":"/work/alpha/sub","state":"live","turn":0,"where":"space-a / tab-2"},
 {"address":"t3","agent":"codex","cwd":"/work/beta","state":"live","status":"blocked","turn":2,"where":"space-b / tab-3"},
 {"agent":"agy","cwd":"/work/none"},
 {"address":"t5","agent":"agy","cwd":"/work/gamma","state":"live","status":"weird","turn":1,"where":"solo"}
]}
"""

@Test func parseLsMapsFields() {
    let ts = HcClient.parseLs(Data(lsJSON.utf8))
    #expect(ts.map(\.address) == ["t1", "t2", "t3", "t5"])  // 주소 없는 항목은 건너뛴다
    #expect(ts[0] == Terminal(address: "t1", harness: .claudeCode, agentRaw: "claude-code", cwd: "/work/alpha", state: "live", status: .working, turn: 4, location: "space-a / tab-1"))
    #expect(ts[1].harness == .other)
    #expect(ts[1].status == .unknown)  // status 없음
    #expect(ts[2].status == .blocked)
    #expect(ts[3].status == .unknown)  // 모르는 값
    #expect(ts[0].tabName == "tab-1")
    #expect(ts[3].tabName == "solo")
    #expect(ts.filter { $0.harness.isAgent }.count == 3)
}

@Test func parseLsGarbage() {
    #expect(HcClient.parseLs(Data("not json".utf8)).isEmpty)
    #expect(HcClient.parseLs(Data("{}".utf8)).isEmpty)
}

@Test func parseStatusText() {
    #expect(HcClient.parseStatusText(Data(#"{"address":"t1","title":"작업 중인 일"}"#.utf8)) == "작업 중인 일")
    #expect(HcClient.parseStatusText(Data(#"{"address":"t1","title":""}"#.utf8)) == nil)
    #expect(HcClient.parseStatusText(Data(#"{"address":"t1"}"#.utf8)) == nil)
}

@Test func heartbeatIsNotChange() {
    #expect(!HcClient.isChange(line: #"{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":1239}}"#))
    #expect(HcClient.isChange(line: #"{"channel":null,"seq":1,"terminals":[]}"#))
}

@Test func locatePrefersEnvThenKnownDirs() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("hcloc-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    func makeExec(_ rel: String) throws -> String {
        let url = root.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return url.path
    }
    let home = root.appendingPathComponent("home").path
    let viaPath = try makeExec("bin/hc")
    let viaHome = try makeExec("home/.local/bin/hc")
    let custom = try makeExec("custom/myhc")
    let env = ["PATH": root.appendingPathComponent("bin").path]

    #expect(HcClient.locate(env: env, home: "/nonexistent") == viaPath)
    #expect(HcClient.locate(env: env, home: home) == viaHome)  // 흔한 위치가 PATH보다 먼저
    #expect(HcClient.locate(env: env.merging(["MMCODE_MONITOR_HC": custom]) { $1 }, home: home) == custom)
    // 환경변수가 실행 불가 경로면 다음 후보로 넘어간다.
    #expect(HcClient.locate(env: env.merging(["MMCODE_MONITOR_HC": "/nonexistent/hc"]) { $1 }, home: home) == viaHome)
}

@Test func writeCommandsRefused() {
    for verb in ["send", "kill", "rm", "interrupt", "run", "server", ""] {
        #expect(throws: HcClient.HcError.forbidden(verb)) { try HcClient.run([verb]) }
    }
    #expect(throws: HcClient.HcError.forbidden("-x")) { try HcClient.read(address: "-x") }
}
