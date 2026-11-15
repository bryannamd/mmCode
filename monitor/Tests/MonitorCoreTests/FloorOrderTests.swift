import Testing
@testable import MonitorCore

@Test func newProjectsAppendedAtEnd() {
    let r = FloorOrder.merge(known: ["a", "b"], current: ["c", "b", "a"])
    #expect(r.known == ["a", "b", "c"])
    #expect(r.visible == ["a", "b", "c"])  // 보이는 순서가 아니라 아는 순서
}

@Test func missingProjectKeepsItsSlot() {
    var r = FloorOrder.merge(known: ["a", "b", "c"], current: ["c", "a"])
    #expect(r.visible == ["a", "c"])
    #expect(r.known == ["a", "b", "c"])  // b는 아는 순서에 남는다
    r = FloorOrder.merge(known: r.known, current: ["b", "c", "a", "d"])
    #expect(r.visible == ["a", "b", "c", "d"])  // 다시 나타난 b는 같은 자리
}

@Test func startsEmptyAndDedupes() {
    #expect(FloorOrder.merge(known: [], current: ["x", "y", "x"]).known == ["x", "y"])
    #expect(FloorOrder.merge(known: ["a", "a"], current: []).visible.isEmpty)
}

@Test func shellOnlyProjectGetsNoFloor() {
    let agent = Terminal(address: "t1", harness: .claudeCode, agentRaw: "claude-code", cwd: "/a")
    let shell = Terminal(address: "t2", harness: .other, agentRaw: "", cwd: "/b")
    let ps = [Project(root: "/a", name: "a", terminals: [agent]), Project(root: "/b", name: "b", terminals: [shell]),
              Project(root: "/c", name: "c", terminals: [shell]), Project(root: "/d", name: "d", plans: [PlanState(plan: "p")])]
    // /b는 셸뿐이라 빠진다. /c는 셸뿐이지만 이미 아는 층이라 남는다. /d는 기록이 있어 남는다.
    #expect(FloorOrder.admit(known: ["/c"], projects: ps).map(\.root) == ["/a", "/c", "/d"])
}
