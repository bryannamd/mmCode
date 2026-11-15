import Foundation
import Testing
@testable import MonitorCore

private func tmpDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("grp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func term(_ addr: String, _ cwd: String, _ agent: String = "claude-code") -> Terminal {
    Terminal(address: addr, harness: Harness(raw: agent), agentRaw: agent, cwd: cwd)
}

@Test func gitRootWalksUp() throws {
    let root = try tmpDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("a/.git"), withIntermediateDirectories: true)   // 폴더
    try fm.createDirectory(at: root.appendingPathComponent("a/b/c"), withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("w/sub"), withIntermediateDirectories: true)
    fm.createFile(atPath: root.appendingPathComponent("w/.git").path, contents: Data("gitdir: x".utf8))  // 워크트리는 파일
    let a = root.appendingPathComponent("a").standardizedFileURL.path
    let w = root.appendingPathComponent("w").standardizedFileURL.path
    #expect(ProjectGrouping.gitRoot(from: root.appendingPathComponent("a/b/c").path) == a)
    #expect(ProjectGrouping.gitRoot(from: a) == a)
    #expect(ProjectGrouping.gitRoot(from: root.appendingPathComponent("w/sub").path) == w)
}

@Test func gitRootFallsBackToCwd() throws {
    let root = try tmpDir()
    defer { try? FileManager.default.removeItem(at: root) }
    // 임시 폴더 위쪽에 .git이 없다고 가정하는 대신, 존재하지 않는 경로로 확인한다.
    #expect(ProjectGrouping.gitRoot(from: "/nonexistent-zz/deep/dir") == "/nonexistent-zz/deep/dir")
}

@Test func groupsByInjectedRoot() {
    let g = ProjectGrouping(findRoot: { $0.hasPrefix("/work/alpha") ? "/work/alpha" : $0 }, readLog: { _ in EventLog.Result() })
    let ps = g.group([term("t1", "/work/alpha"), term("t2", "/work/beta"), term("t3", "/work/alpha/sub", "zsh")])
    #expect(ps.map(\.root) == ["/work/alpha", "/work/beta"])
    #expect(ps[0].name == "alpha")
    #expect(ps[0].terminals.map(\.address) == ["t1", "t3"])
    #expect(ps[0].agents.map(\.address) == ["t1"])
    #expect(!ps[0].hasEvents)
}

@Test func plansLoadedAndCached() throws {
    let root = try tmpDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let dir = root.appendingPathComponent(".mmcode")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("events.jsonl")
    let line1 = #"{"ts":"2026-11-15T10:00:00+09:00","type":"unit.phase","plan":"p","unit":"U1","data":{"to":"build"}}"#
    try (line1 + "\n").write(to: file, atomically: true, encoding: .utf8)

    var reads = 0
    let g = ProjectGrouping(findRoot: { _ in root.path }, readLog: { reads += 1; return EventLog.read(url: $0) })
    let t = [term("t1", root.path)]
    #expect(g.group(t)[0].plans.first?.units.first?.phase == .build)
    #expect(g.group(t)[0].hasEvents)
    #expect(reads == 1)  // 같은 크기·수정 시각이면 다시 읽지 않는다

    // 줄을 추가하면 크기가 달라져 다시 읽는다.
    let line2 = #"{"ts":"2026-11-15T10:01:00+09:00","type":"unit.phase","plan":"p","unit":"U1","data":{"to":"verify"}}"#
    let h = try FileHandle(forWritingTo: file)
    try h.seekToEnd()
    try h.write(contentsOf: Data((line2 + "\n").utf8))
    try h.close()
    #expect(g.group(t)[0].plans.first?.units.first?.phase == .verify)
    #expect(reads == 2)

    // 파일이 사라지면 빈 목록, 캐시도 지운다.
    try FileManager.default.removeItem(at: file)
    #expect(g.group(t)[0].plans.isEmpty)
}

@Test func noEventsFile() throws {
    let root = try tmpDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let g = ProjectGrouping(findRoot: { _ in root.path })
    #expect(g.group([term("t1", root.path)])[0].plans.isEmpty)
}
