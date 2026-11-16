import Foundation
import Testing
@testable import MonitorCore

private func fixture(_ name: String) -> [String] {
    let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")!
    return try! String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
}

private func ts(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func phasesFlow() throws {
    let r = EventLog.reduce(lines: fixture("phases"))
    #expect(r.plans.count == 1)
    let p = r.plans[0]
    #expect(p.plan == "demo")
    // 번호 순, -fix는 본 단위 뒤, U10은 U2 뒤.
    #expect(p.units.map(\.id) == ["U1", "U2", "U2-fix1", "U10"])
    #expect(p.units[0].title == "자료 층")
    #expect(p.units[3].phase == .queued)  // plan.approve만 있는 단위
    #expect(p.units[1].phase == .build)
    let u1 = p.units[0]
    #expect(u1.phase == .done)
    #expect(u1.commit == "abc1234")
    #expect(u1.backReason == nil)  // 마지막 전환(review→done)에는 사유가 없다
    #expect(u1.owner?.terminal == "t1")
    #expect(u1.updated == ts("2026-11-15T10:09:00+09:00"))
    #expect(p.updated == ts("2026-11-15T10:10:00+09:00"))
    // 소수 초가 있는 ts를 읽었다(건너뛰지 않았다).
    #expect(r.processed == 12)
    #expect(r.skipped == 1)  // telepathy
}

@Test func backwardKeepsReason() {
    let lines = Array(fixture("phases").prefix(5))
    let u = EventLog.reduce(lines: lines).plans[0].units.first { $0.id == "U1" }!
    #expect(u.phase == .build)
    #expect(u.backReason == "시험 실패")
}

@Test func evidenceKept() {
    let u = EventLog.reduce(lines: fixture("phases")).plans[0].units[0]
    // 검증에 다시 들어가면 1회차의 실패 증거는 비워진다. 2회차의 두 건만 남는다.
    #expect(u.evidence.count == 2)
    #expect(u.evidence[0] == Evidence(kind: .cmd, pass: true, command: "swift test", exit: 0, reason: nil, path: nil, ts: ts("2026-11-15T10:06:00+09:00")))
    #expect(u.latest(.cmd)?.pass == true)
    #expect(u.latest(.manual)?.path == "docs/relay/demo/goal/U1.png")
    #expect(u.latest(.review) == nil)
}

@Test func actorsMerged() {
    let p = EventLog.reduce(lines: fixture("phases")).plans[0]
    // t2의 첫 이벤트에 model·effort가 있고 이후 이벤트에는 빠져 있어도 값이 유지된다.
    #expect(p.actors["t2"] == Actor(terminal: "t2", harness: .codex, model: "gpt-x", effort: "medium"))
    #expect(p.actors["t1"]?.model == "claude-fable-5-2")
    #expect(p.actors["t1"]?.harness == .claudeCode)
}

@Test func haltAndResume() {
    let lines = fixture("halts")
    // 단계별로 본다.
    var p = EventLog.reduce(lines: Array(lines.prefix(4))).plans[0]
    #expect(p.units.first { $0.id == "U1" }?.halt?.kind == .decision)
    #expect(p.halts.map(\.reason) == ["limit:iterations"])
    // blocked:U3은 이벤트의 단위(U2)가 아니라 U3에 걸린다.
    #expect(p.units.first { $0.id == "U3" }?.halt?.kind == .unitBlocked)
    #expect(p.units.first { $0.id == "U2" }?.halt == nil)
    // rotate·done은 멈춤이 아니다.
    p = EventLog.reduce(lines: Array(lines.prefix(6))).plans[0]
    #expect(p.allHalts.count == 3)
    p = EventLog.reduce(lines: Array(lines.prefix(7))).plans[0]
    #expect(p.halts.map(\.reason) == ["limit:iterations", "stop-after"])
    // 사유를 지정한 풀림은 그 멈춤만 푼다.
    p = EventLog.reduce(lines: Array(lines.prefix(8))).plans[0]
    #expect(p.units.first { $0.id == "U1" }?.halt == nil)
    #expect(p.halts.count == 2)
    p = EventLog.reduce(lines: lines).plans[0]
    #expect(p.halts.map(\.reason) == ["limit:iterations"])
    #expect(p.units.first { $0.id == "U3" }?.halt != nil)
}

@Test func resumeWithoutReasonClearsUnitOnly() {
    let lines = [
        #"{"ts":"2026-11-15T11:00:00+09:00","type":"unit.halt","plan":"p","unit":"U1","data":{"reason":"decision"}}"#,
        #"{"ts":"2026-11-15T11:01:00+09:00","type":"unit.halt","plan":"p","data":{"reason":"expired"}}"#,
        #"{"ts":"2026-11-15T11:02:00+09:00","type":"unit.resume","plan":"p","unit":"U1","data":{}}"#,
    ]
    var p = EventLog.reduce(lines: lines).plans[0]
    #expect(p.units[0].halt == nil)
    #expect(p.halts.count == 1)
    p = EventLog.reduce(lines: lines + [#"{"ts":"2026-11-15T11:03:00+09:00","type":"unit.resume","plan":"p","data":{}}"#]).plans[0]
    #expect(p.halts.isEmpty)
}

@Test func brokenLinesSkipped() {
    let r = EventLog.reduce(lines: fixture("broken"))
    #expect(r.plans.count == 1)  // ghost 계획은 유효한 이벤트가 없어 생기지 않는다
    #expect(r.plans[0].units[0].phase == .verify)
    #expect(r.processed == 2)
    // 깨진 줄, 모르는 type, 나쁜 ts, ts 없음, 모르는 단계, ghost, 쓰다 만 마지막 줄. 빈 줄은 세지 않는다.
    #expect(r.skipped == 7)
}

@Test func twoPlansSeparate() {
    let r = EventLog.reduce(lines: fixture("two-plans"))
    #expect(r.plans.map(\.plan) == ["alpha", "beta"])
    #expect(r.plans[0].units[0].phase == .build)
    #expect(r.plans[1].units[0].phase == .done)
    #expect(r.plans[0].halts.count == 1)
    #expect(r.plans[1].halts.isEmpty)
}

// 확정 형식(phase.sh aa5597d). 계획 p와 폴더 기록(plan -)이 섞여 있다.
@Test func decisionsFromConfirmedFormat() {
    let r = EventLog.reduce(lines: Array(fixture("decisions").prefix(2)))
    let d1 = r.plans[0].decisions[0]
    #expect(d1.recommendation == "아니오" && d1.options == ["예", "아니오"] && d1.blocks == ["U3"] && d1.impact == "배포 지연")
    #expect(d1.asker?.terminal == "t1" && d1.isOpen)
    // 결정으로 멈춘 단위는 그 결정을 가리킨다.
    #expect(r.plans[0].units.first { $0.id == "U3" }?.halt?.decision == "D1")

    let all = EventLog.reduce(lines: fixture("decisions"))
    let p = all.plans[0]
    #expect(all.plans.map(\.plan) == ["p"], "폴더 기록은 다른 계획이 있으면 거기에 합친다")
    #expect(p.decisions.map(\.id) == ["D1", "D2"])
    #expect(p.decisions[0].answer == "아니오")
    #expect(p.decisions[1].recommendation == "그대로", "옛 키 recommendation도 읽는다")
    #expect(p.decisions[1].blocks.isEmpty && p.openDecisions.map(\.id) == ["D2"])
    #expect(all.skipped == 1, "없는 결정의 답")
}

@Test func stopsStayOpenUntilResume() {
    let before = EventLog.reduce(lines: Array(fixture("decisions").prefix(12))).plans[0]
    #expect(before.directives.map(\.id) == ["I1", "I2", "I3"])
    let i1 = before.directives[0], i2 = before.directives[1], i3 = before.directives[2]
    #expect(i1.status == .applied && i1.isOpen, "적용된 단위 후 정지도 계속 전까지 열려 있다")
    #expect(i2.status == .rejected && !i2.isOpen && i2.reason == "계획자가 거부" && i2.terminal == "t2")
    #expect(i3.status == .applied && i3.isOpen)
    #expect(before.openStops.map(\.id) == ["I1", "I3"])
    #expect(before.units.first { $0.id == "U4" }?.halt?.directive == "I1")

    let after = EventLog.reduce(lines: fixture("decisions")).plans[0]
    // 폴더의 계속(I4)이 계획 p의 즉시 중단(I3)도 닫는다.
    #expect(after.directives.filter(\.closed).map(\.id) == ["I1", "I3"])
    #expect(after.openStops.isEmpty)
    let i4 = after.directives.last!
    #expect(i4.kind == .resume && i4.status == .applied && !i4.isOpen, "계속은 접수가 곧 적용이다")
    #expect(after.units.first { $0.id == "U4" }?.halt == nil)
}

@Test func folderOnlyPlanStays() {
    let lines = fixture("decisions").filter { $0.contains(#""plan":"-""#) }
    let r = EventLog.reduce(lines: lines)
    #expect(r.plans.map(\.plan) == ["-"])
    #expect(r.plans[0].decisions.map(\.id) == ["D2"])
}

@Test func sessionUpdatesActorOnly() {
    let p = EventLog.reduce(lines: fixture("decisions")).plans[0]
    #expect(p.actors["t7"] == Actor(terminal: "t7", harness: .codex, model: "gpt-x", effort: "high"))
}

@Test func emptyInput() {
    #expect(EventLog.reduce(lines: []) == EventLog.Result())
    #expect(EventLog.read(url: URL(fileURLWithPath: "/nonexistent/events.jsonl")) == EventLog.Result())
}

@Test func readFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("evlog-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    try fixture("two-plans").joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    let r = EventLog.read(url: url)
    #expect(r.plans.count == 2)
    #expect(r.processed == 3)
}

// 검수 1회차의 필수 수정을 잡는 시험.
private func ev(_ type: String, _ unit: String, _ data: String, at s: Int = 0) -> String {
    "{\"ts\":\"2026-11-16T00:00:\(String(format: "%02d", s))+09:00\",\"type\":\"\(type)\",\"plan\":\"p\",\"unit\":\"\(unit)\",\"data\":\(data)}"
}

@Test func reentryClearsPastRoundEvidenceAndCommit() {
    let r = EventLog.reduce(lines: [
        ev("unit.phase", "U1", #"{"from":"queued","to":"build"}"#, at: 1),
        ev("unit.commit", "U1", #"{"repo":".","hash":"abc"}"#, at: 2),
        ev("unit.phase", "U1", #"{"from":"build","to":"verify"}"#, at: 3),
        ev("check.result", "U1", #"{"kind":"cmd","pass":false,"exit":1}"#, at: 4),
        ev("unit.phase", "U1", #"{"from":"verify","to":"build","reason":"시험 실패"}"#, at: 5),
        ev("unit.phase", "U1", #"{"from":"build","to":"verify"}"#, at: 6),
    ])
    let u = r.plans[0].units[0]
    #expect(u.evidence.isEmpty)
    #expect(u.commit == nil)
}

@Test func lineSeparatorInsideReasonIsKept() throws {
    let line = ev("unit.phase", "U1", "{\"from\":\"queued\",\"to\":\"build\",\"reason\":\"a\u{2028}b\"}")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mmcode-\(UUID().uuidString).jsonl")
    try Data((line + "\r\n" + line + "\n").utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let r = EventLog.read(url: url)
    #expect(r.processed == 2)
    #expect(r.skipped == 0)
    #expect(r.plans.first?.units.first?.backReason == "a\u{2028}b")
}
