import Foundation
import Testing
@testable import MonitorCore

private final class Counter: @unchecked Sendable {
    let sem = DispatchSemaphore(value: 0)
    func hit() { sem.signal() }
    /// 알림이 올 때까지 기다린다. 시간 안에 오면 true.
    func wait(_ seconds: Double = 3) -> Bool { sem.wait(timeout: .now() + seconds) == .success }
    func drain() { while sem.wait(timeout: .now() + 0.2) == .success {} }
}

@Test func notifiesOnAppendAndCreate() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent(".mmcode/events.jsonl").path  // 폴더도 파일도 아직 없다

    let c = Counter()
    let w = FileWatcher(path: path, onChange: c.hit)
    w.start()
    defer { w.stop() }

    try FileManager.default.createDirectory(atPath: dir.path + "/.mmcode", withIntermediateDirectories: true)
    #expect(c.wait())
    c.drain()
    FileManager.default.createFile(atPath: path, contents: Data("a\n".utf8))
    #expect(c.wait())
    c.drain()

    // 이제 파일을 직접 보고 있다. 추가 쓰기가 알려진다.
    let h = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try h.seekToEnd()
    try h.write(contentsOf: Data("b\n".utf8))
    try h.close()
    #expect(c.wait())
    c.drain()

    // 이름 바꿔 덮어써도(원자 쓰기) 새 파일을 이어서 본다.
    try Data("c\n".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    #expect(c.wait())
    c.drain()
    let h2 = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try h2.seekToEnd()
    try h2.write(contentsOf: Data("d\n".utf8))
    try h2.close()
    #expect(c.wait())
}

@Test func stopSilences() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID().uuidString).jsonl").path
    FileManager.default.createFile(atPath: path, contents: Data())
    defer { try? FileManager.default.removeItem(atPath: path) }
    let c = Counter()
    let w = FileWatcher(path: path, onChange: c.hit)
    w.start()
    w.stop()
    try Data("x\n".utf8).write(to: URL(fileURLWithPath: path))
    #expect(!c.wait(0.5))
}
