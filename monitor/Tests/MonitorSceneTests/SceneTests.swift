import CoreGraphics
import CoreText
import Foundation
import MonitorCore
import Testing
@testable import MonitorScene

// MARK: 재료

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func term(_ a: String, _ tab: String, _ h: Harness = .claudeCode, _ st: AgentStatus = .working) -> Terminal {
    Terminal(address: a, harness: h, agentRaw: h.rawValue, cwd: "/p", status: st, location: "p / \(tab)")
}

private func proj(_ terms: [Terminal], _ plan: PlanState?, name: String = "p") -> Project {
    Project(root: "/" + name, name: name, terminals: terms, plans: plan.map { [$0] } ?? [])
}

private func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    let d = img.dataProvider!.data! as Data, i = y * img.bytesPerRow + x * 4
    return [d[i], d[i + 1], d[i + 2], d[i + 3]]
}

private func rgb(_ hex: String) -> [UInt8] { let c = RGBA(hex); return [c.r, c.g, c.b, 255] }

// MARK: 털 무늬

@Test func coatFollowsHarnessAndModel() {
    #expect(SceneBuilder.coat(harness: .claudeCode, model: "claude-fable-5-2") == .tuxedo)
    #expect(SceneBuilder.coat(harness: .claudeCode, model: "claude-opus-5-5") == .calico)
    #expect(SceneBuilder.coat(harness: .claudeCode, model: "claude-sonnet-5-5") == .tabby)
    #expect(SceneBuilder.coat(harness: .claudeCode, model: "claude-haiku-5-5") == .white)
    #expect(SceneBuilder.coat(harness: .claudeCode, model: "gpt-x") == .catGray)
    #expect(SceneBuilder.coat(harness: .claudeCode, model: nil) == .catGray)
    #expect(SceneBuilder.coat(harness: .codex, model: "gpt-5.5") == .beagle)
    #expect(SceneBuilder.coat(harness: .codex, model: "gpt-5.5-mini") == .dogSpot)
    #expect(SceneBuilder.coat(harness: .agy, model: "gemini-3-flash") == .frogSpot)
    #expect(SceneBuilder.coat(harness: .agy, model: nil) == .frog)
}

// MARK: 단계와 자리

@Test func quietDemoPlacesBoxesByPhase() {
    let v = SceneBuilder.office(Demo.quiet.world, project: 0, night: false)
    let s = v.scene
    let place = Dictionary(uniqueKeysWithValues: s.boxes.map { ($0.id, $0.place) })
    #expect(place["U1"] == .done(slot: 0) && place["U2"] == .done(slot: 1))
    #expect(place["U3"] == .desk(1))
    #expect(place["U4"] == .backlog(slot: 0) && place["U6"] == .backlog(slot: 2))
    let a = Dictionary(uniqueKeysWithValues: s.actors.map { ($0.id, $0) })
    #expect(a["t1"]?.spot == .desk(0) && a["t1"]?.pose == .work && a["t1"]?.coat == .tuxedo)
    #expect(a["t2"]?.spot == .desk(1), "U3의 담당자는 상자가 있는 책상에 앉는다")
    #expect(a["t3"]?.spot == .sofa(0) && a["t3"]?.pose == .sleep && a["t3"]?.coat == .beagle)
    #expect(a["t2"]?.name == "일꾼")
    #expect(v.roof.cells == [true, true, false, false, false, false] && v.roof.count == "완료 2/6" && v.roof.isDemo)
    #expect(v.ground.title == "조용합니다. 둘이 일하고 하나는 쉽니다")
    #expect(v.ground.detail == "U3 모니터 조회판: 구현 단계")
    #expect(v.ground.buttons.map(\.label) == ["단위 후 정지", "중단"])
}

@Test func verifyAndReviewGoToBenchAndScreen() {
    let plan = PlanState(plan: "x", units: [
        UnitState(id: "U1", phase: .verify, evidence: [Evidence(kind: .cmd, pass: true, ts: t0)], owner: Actor(terminal: "a")),
        UnitState(id: "U2", phase: .review, owner: Actor(terminal: "b")),
    ])
    let s = SceneBuilder.office(World(projects: [proj([term("a", "A"), term("b", "B", .codex)], plan)]), project: 0, night: false).scene
    #expect(s.actors.map(\.spot) == [.test, .ui])
    #expect(s.boxes.map(\.place) == [.test, .ui])
    #expect(s.lamp == .ok)
}

@Test func decisionAskerStandsAtBell() {
    let v = SceneBuilder.office(Demo.decision.world, project: 0, night: false)
    let main = v.scene.actors.first { $0.id == "t1" }
    #expect(main?.spot == .bell && main?.pose == .ask)
    #expect(v.scene.bell)
    #expect(v.ground.turn && v.ground.title == "정본을 이벤트 파일로 옮길까요?")
    #expect(v.ground.detail == "결정 대기. U4와 U5가 이 답을 기다립니다")
    #expect(v.ground.buttons.first == GroundButton("옮긴다", .answer(decision: "D1", text: "옮긴다"), primary: true))
    #expect(v.ground.icon == .face(.tuxedo, .ask))
}

@Test func blockedUnitTurnsLampRedAndGroundPink() {
    let v = SceneBuilder.office(Demo.blocked.world, project: 0, night: false)
    #expect(v.scene.lamp == .fail)
    #expect(v.scene.boxes.first { $0.id == "U3" }?.blocked == true)
    #expect(v.scene.actors.first { $0.id == "t2" }?.spot == .test, "맡은 단위가 있는 쉬는 담당자는 그 자리에 선다")
    #expect(v.ground.title == "U3 단위 막힘")
    #expect(v.ground.detail == "검사 명령 실패 3/12. 일꾼이 멈췄습니다")
    #expect(v.ground.buttons.map(\.label) == ["일꾼에게 메시지"])
    #expect(v.scene.bubbles.allSatisfy { $0.actorID != "t2" }, "막힌 담당자에게는 말풍선을 쓰지 않는다")
}

@Test func stoppedShowsSignAndContinue() {
    let v = SceneBuilder.office(Demo.stopped.world, project: 0, night: false)
    #expect(v.scene.stopSign)
    #expect(v.scene.actors.allSatisfy { $0.pose == .stopped })
    #expect(!v.ground.turn && v.ground.icon == .stop && v.ground.title == "사용자 정지 상태입니다")
    #expect(v.ground.buttons.map(\.label) == ["계속"])
}

// MARK: 지반 우선순위

@Test func groundPriorityOrder() {
    let ts = t0
    func world(decision: Bool, blocked: Bool, env: Bool, input: Bool, stop: Bool) -> World {
        var plan = PlanState(plan: "x", units: [UnitState(id: "U1", phase: .build, halt: blocked ? Halt(reason: "blocked:U1", unit: "U1", ts: ts) : nil, owner: Actor(terminal: "a"))])
        if decision { plan.decisions = [Decision(id: "D", question: "Q?", ts: ts)] }
        if env { plan.halts.append(Halt(reason: "limit:iterations", unit: nil, ts: ts)) }
        if stop { plan.halts.append(Halt(reason: "interrupt", unit: nil, ts: ts)) }
        return World(projects: [proj([term("a", "일꾼", .claudeCode, input ? .blocked : .working)], plan)])
    }
    func title(_ w: World) -> String { SceneBuilder.office(w, project: 0, night: false).ground.title }
    #expect(title(world(decision: true, blocked: true, env: true, input: true, stop: true)) == "Q?")
    #expect(title(world(decision: false, blocked: true, env: true, input: true, stop: true)) == "U1 단위 막힘")
    #expect(title(world(decision: false, blocked: false, env: true, input: true, stop: true)) == "한도 초과로 멈췄습니다")
    let input = SceneBuilder.office(world(decision: false, blocked: false, env: false, input: true, stop: true), project: 0, night: false).ground
    #expect(input.title == "일꾼이 터미널에서 입력을 기다립니다" && input.buttons.isEmpty && input.turn)
    #expect(title(world(decision: false, blocked: false, env: false, input: false, stop: true)) == "사용자 정지 상태입니다")
    #expect(title(world(decision: false, blocked: false, env: false, input: false, stop: false)).hasPrefix("조용합니다"))
}

@Test func otherFloorAlertOnRoofAndBuilding() {
    let w = Demo.otherFloorAlert.world
    let v = SceneBuilder.office(w, project: 0, night: false)
    #expect(v.roof.alert == RoofModel.Alert(floor: 2, long: "모바일 앱 층 한도 초과", short: "다른 층 1건"))
    #expect(v.ground.title == "이 층은 조용합니다")
    let b = SceneBuilder.building(w, night: false)
    #expect(b.ground.title == "모바일 앱 층: 환경·한도" && b.ground.detail == "한도 초과로 일꾼이 멈췄습니다")
    #expect(b.ground.buttons == [GroundButton("층으로 가기", .enterFloor(2), primary: true)])
    #expect(b.scene.floors[2].alert == .error && b.roof.alert == nil && b.roof.count == "4개 층")
    // 결정 대기 층이 있으면 그것이 더 급하다.
    #expect(SceneBuilder.building(Demo.building.world, night: false).ground.title == "mmCode 층: 결정 대기")
}

// MARK: 넘침과 기록 없음

@Test func overflowKeepsCapacityAndCountsRest() {
    let terms = (0..<10).map { term("a\($0)", "A\($0)") }
    let units = (1...10).map { UnitState(id: "U\($0)") } + (11...16).map { UnitState(id: "U\($0)", phase: .done, updated: t0.addingTimeInterval(Double($0))) }
    let v = SceneBuilder.office(World(projects: [proj(terms, PlanState(plan: "x", units: units))]), project: 0, night: false)
    #expect(v.scene.actors.count == 5 && v.scene.hiddenActors == 5, "책상 3, 소파 2")
    #expect(v.list.sections[0].rows.count == 10)
    let backlog = v.scene.boxes.filter { if case .backlog = $0.place { true } else { false } }.map(\.id)
    let done = v.scene.boxes.filter { if case .done = $0.place { true } else { false } }.map(\.id)
    #expect(backlog == ["U1", "U2", "U3", "U4"])
    #expect(done == ["U13", "U14", "U15", "U16"], "완료는 최근 것부터 4개")
    #expect(v.scene.hiddenBoxes == 8)
}

@Test func projectWithoutEventsHasNoBoxes() {
    let v = SceneBuilder.office(World(projects: [proj([term("a", "A", .claudeCode, .idle)], nil)]), project: 0, night: false)
    #expect(v.scene.boxes.isEmpty && v.roof.cells.isEmpty && v.roof.count == nil)
    #expect(v.scene.actors.count == 1 && v.ground.buttons.isEmpty)
}

// MARK: 건물 보이는 범위

@Test func buildingVisibleRange() {
    let w = World(projects: (0..<6).map { proj($0 == 2 ? [] : [term("a\($0)", "A")], nil, name: "p\($0)") })
    let b = SceneBuilder.building(w, firstFloor: 1, night: false).scene
    #expect(b.floors.map(\.index) == [1, 2, 3, 4] && b.moreAbove && b.moreBelow)
    #expect(b.hits.first?.kind == .floor(1))
    let end = SceneBuilder.building(w, firstFloor: 99, night: false).scene
    #expect(end.firstFloor == 2 && end.moreAbove && !end.moreBelow)
    let top = SceneBuilder.building(w, night: false).scene
    #expect(!top.moreAbove && top.moreBelow)
    // 에이전트가 없는 층(p2)은 어둡다.
    let img = SceneRenderer.render(b, frame: 0).base
    let y2 = BuildingLayout.floorY + 1 * BuildingLayout.floorH + 3, y1 = BuildingLayout.floorY + 3
    #expect(pixel(img, 200, y2) != rgb("#d9d2ff") && pixel(img, 200, y1) == rgb("#ffd9c2"))
    // 위 화살표는 시안에 없는 추가라 해치 색으로 작게 그린다.
    #expect(pixel(img, 118, 1) == rgb("#4a548c"))
}

// MARK: 그리기

@Test func officeRenderSizeColorsAndFrames() {
    let s = SceneBuilder.office(Demo.decision.world, project: 0, night: false).scene
    let f0 = SceneRenderer.render(s, frame: 0), f1 = SceneRenderer.render(s, frame: 1)
    #expect(f0.base.width == 240 && f0.base.height == 108 && f0.fx.width == 240)
    #expect(pixel(f0.base, 0, 0) == rgb("#232845"))   // 천장 판
    #expect(pixel(f0.base, 6, 5) == rgb("#c8eee0"))   // 벽
    #expect(pixel(f0.base, 100, 75) == rgb("#f4bd6c")) // 바닥
    #expect(pixel(f0.fx, 134, 90) == rgb("#ff4f9a"))   // 분홍 벨은 주의 층에만
    #expect(pixel(f0.base, 134, 90) == rgb("#ffc23d"))
    #expect(pixel(f0.fx, 5, 5)[3] == 0)
    #expect(f0.fx.dataProvider!.data! as Data != f1.fx.dataProvider!.data! as Data, "손 흔들기와 벨 울림")
    let night = SceneRenderer.render(SceneBuilder.office(Demo.decision.world, project: 0, night: true).scene, frame: 0)
    #expect(pixel(night.base, 6, 5) == rgb("#2f3b76"))
}

@Test func workingFramesDiffer() {
    let s = SceneBuilder.office(Demo.quiet.world, project: 0, night: false).scene
    #expect(SceneRenderer.render(s, frame: 0).base.dataProvider!.data! as Data != SceneRenderer.render(s, frame: 1).base.dataProvider!.data! as Data)
    // 일하는 책상의 모니터가 켜진다.
    #expect(pixel(SceneRenderer.render(s, frame: 0).base, 72, 54) == rgb("#eafcff"))
    #expect(pixel(SceneRenderer.render(s, frame: 0).base, 128, 54) == rgb("#55608a"))
}

@Test func iconAndFont() {
    let i = SceneRenderer.icon(.face(.beagle, .sleep))
    #expect(i.width == 16 && i.height == 16)
    #expect(Fonts.register() && Fonts.register(), "두 번 불러도 성공")
    #expect(CTFontCopyPostScriptName(CTFontCreateWithName(Fonts.jua as CFString, 12, nil)) as String == Fonts.jua)
}

@Test func josaFollowsFinalConsonant() {
    #expect(SceneBuilder.josa("일꾼", "이", "가") == "이" && SceneBuilder.josa("계획자", "이", "가") == "가")
    #expect(SceneBuilder.josa("U4", "과", "와") == "와" && SceneBuilder.josa("U3", "과", "와") == "과")
    #expect(SceneBuilder.josa("한도 초과", "으로", "로") == "로")
}

@Test func numericTabNameGetsSpaceName() {
    #expect(SceneBuilder.name(Terminal(address: "t1", harness: .claudeCode, agentRaw: "claude-code", cwd: "/x", location: "Shop / 1")) == "Shop 1")
    #expect(SceneBuilder.name(Terminal(address: "t1", harness: .claudeCode, agentRaw: "claude-code", cwd: "/x", location: "Shop / 검수")) == "검수")
    #expect(SceneBuilder.name(Terminal(address: "t1", harness: .claudeCode, agentRaw: "claude-code", cwd: "/x", location: "")) == "t1")
    #expect(SceneBuilder.brief("가나다라마바사아자차카타파하가나다라마바") == "가나다라마바사아자차카타파하가나다라…")
    #expect(SceneBuilder.brief("Read 진행 기록") == "Read 진행 기록")
}

// 검수 1회차의 필수 수정을 잡는 시험.
private func oneUnitWorld(_ unit: UnitState, status: AgentStatus = .working) -> World {
    let t = Terminal(address: "t1", harness: .claudeCode, agentRaw: "claude-code", cwd: "/x", status: status, location: "s / 계획자")
    return World(projects: [Project(root: "/x", name: "x", terminals: [t], plans: [PlanState(plan: "p", units: [unit], updated: Date(timeIntervalSince1970: 1))])])
}

@Test func decisionHaltWithoutAskIsYourTurn() {
    let halt = Halt(reason: "decision", unit: "U1", ts: Date(timeIntervalSince1970: 1))
    let w = oneUnitWorld(UnitState(id: "U1", phase: .build, halt: halt, owner: Actor(terminal: "t1")))
    let v = SceneBuilder.office(w, project: 0, night: false)
    #expect(v.ground.turn)
    #expect(v.scene.bell)
    #expect(v.scene.actors.first?.pose == .ask)
}

@Test func verifyLampRunsBeforeAnyResult() {
    let w = oneUnitWorld(UnitState(id: "U1", phase: .verify, owner: Actor(terminal: "t1")))
    #expect(SceneBuilder.office(w, project: 0, night: false).scene.lamp == .run)
}

// MARK: 결정 선택지와 열린 지시

private func decisionGround(_ d: Decision, halt: Halt? = nil, others: [Decision] = []) -> GroundModel {
    let plan = PlanState(plan: "p", units: [UnitState(id: "U1", phase: .build, halt: halt)], decisions: others + [d], updated: t0)
    return SceneBuilder.office(World(projects: [proj([term("a", "A")], plan)]), project: 0, night: false).ground
}

@Test func optionsBecomeButtons() {
    Fonts.register()
    let fit = decisionGround(Decision(id: "D1", question: "Q", recommendation: "아니오", options: ["예", "아니오"], ts: t0)).buttons
    #expect(fit == [GroundButton("예", .answer(decision: "D1", text: "예")), GroundButton("아니오", .answer(decision: "D1", text: "아니오"), primary: true)])
    // 다 들어가지 않으면 앞의 것만 두고 나머지는 "다르게 답하기"로 넣는다.
    let long = ["첫째 선택지입니다", "둘째 선택지입니다", "셋째 선택지입니다"]
    let some = decisionGround(Decision(id: "D1", question: "Q", recommendation: long[0], options: long, ts: t0)).buttons
    #expect(some.map(\.label) == [long[0], "다르게 답하기"] && some[0].primary && some[1].action == .reply(decision: "D1"))
    #expect(SceneBuilder.fits(some.map(\.label)) && !SceneBuilder.fits(long))
    let none = decisionGround(Decision(id: "D1", question: "Q", options: [String(repeating: "아주 긴 선택지 ", count: 6)], ts: t0)).buttons
    #expect(none == [GroundButton("다르게 답하기", .reply(decision: "D1"), primary: true)])
}

@Test func haltShowsItsOwnDecision() {
    let d2 = Decision(id: "D2", question: "멈춘 단위의 질문", ts: t0)
    let g = decisionGround(d2, halt: Halt(reason: "decision", unit: "U1", ts: t0, decision: "D2"), others: [Decision(id: "D1", question: "폴더 질문", ts: t0)])
    #expect(g.title == "멈춘 단위의 질문")
}

@Test func openStopDirectives() {
    func office(_ dirs: [Directive]) -> OfficeView {
        let plan = PlanState(plan: "p", units: [UnitState(id: "U1", phase: .build)], directives: dirs, updated: t0)
        return SceneBuilder.office(World(projects: [proj([term("a", "A", .claudeCode, .idle)], plan)]), project: 0, night: false)
    }
    let received = office([Directive(id: "I1", kind: .stopAfter, ts: t0)])
    #expect(received.scene.stopSign && received.ground.detail == "이 단위를 마치면 멈춥니다")
    #expect(received.ground.buttons.first == GroundButton("정지 접수됨", .stopAfter, disabled: true))
    // 즉시 중단은 halt 없이 적용만 적힌다. 그래도 사용자 정지다.
    let applied = office([Directive(id: "I1", kind: .interrupt, status: .applied, ts: t0)])
    #expect(applied.ground.title == "사용자 정지 상태입니다" && applied.ground.detail.hasPrefix("즉시 중단을 적용했습니다"))
    #expect(applied.scene.actors.allSatisfy { $0.pose == .stopped })
    let closed = office([Directive(id: "I1", kind: .interrupt, status: .applied, closed: true, ts: t0), Directive(id: "I2", kind: .resume, status: .applied, ts: t0)])
    #expect(!closed.scene.stopSign && closed.ground.title.hasPrefix("조용합니다"))
}

@Test func decisionsFromEveryPlan() {
    func ev(_ ts: String, _ type: String, _ plan: String, _ unit: String, _ data: String) -> String {
        #"{"ts":"2026-11-16T10:\#(ts):00+09:00","type":"\#(type)","plan":"\#(plan)","unit":"\#(unit)","data":\#(data)}"#
    }
    let plans = EventLog.reduce(lines: [
        ev("00", "unit.phase", "A", "U1", #"{"from":"queued","to":"build"}"#),
        ev("01", "decision.ask", "A", "U1", #"{"id":"D1","question":"A의 질문","options":[]}"#),
        ev("01", "unit.halt", "A", "U1", #"{"reason":"decision","decision":"D1"}"#),
        ev("02", "decision.ask", "-", "-", #"{"id":"D2","question":"폴더 질문","options":[]}"#),
        ev("05", "unit.phase", "B", "U1", #"{"from":"queued","to":"build"}"#),
        ev("06", "decision.ask", "B", "-", #"{"id":"D3","question":"B의 질문","options":[]}"#),
    ]).plans
    let p = proj([term("a", "A")], nil)
    let w = World(projects: [Project(root: p.root, name: p.name, terminals: p.terminals, plans: plans)])
    #expect(w.projects[0].activePlan?.plan == "B")
    let v = SceneBuilder.office(w, project: 0, night: false)
    // 보는 계획(B)이 아닌 A의 결정과 멈춘 단위가 먼저 나온다.
    #expect(v.ground.title == "A의 질문" && v.ground.detail == "결정 대기. A 계획의 U1이 이 답을 기다립니다")
    #expect(v.scene.bell)
    #expect(v.list.sections.first { $0.title == "열린 결정" }?.rows.map(\.title) == ["D1", "D2", "D3"])
    #expect(SceneBuilder.building(w, night: false).scene.floors[0].alert == .ask)
}

@Test func continueOnlyWhenDirectiveCanResume() {
    let t = term("a", "A", .claudeCode, .idle)
    func ground(_ plan: PlanState) -> GroundModel { SceneBuilder.office(World(projects: [proj([t], plan)]), project: 0, night: false).ground }
    // 지시 연결 없는 손으로 쓴 정지는 resume으로 풀리지 않는다.
    let hand = ground(PlanState(plan: "p", units: [UnitState(id: "U1", halt: Halt(reason: "stop-after", unit: "U1", ts: t0), owner: Actor(terminal: "a"))], updated: t0))
    #expect(hand.buttons.isEmpty && hand.detail.hasSuffix("터미널 a에서 계속하세요"))
    let linked = ground(PlanState(plan: "p", units: [UnitState(id: "U1", halt: Halt(reason: "stop-after", unit: "U1", ts: t0, directive: "I1"))], updated: t0))
    #expect(linked.buttons.map(\.label) == ["계속"])
    let env = ground(PlanState(plan: "p", halts: [Halt(reason: "limit:iterations", unit: nil, ts: t0)], updated: t0))
    #expect(env.buttons.isEmpty && env.detail.hasSuffix("터미널 a에서 계속하세요"))
}
