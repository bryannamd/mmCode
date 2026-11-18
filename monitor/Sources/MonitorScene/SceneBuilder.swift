import CoreGraphics
import CoreText
import Foundation
import MonitorCore

// MonitorCore의 World/Project를 장면 값으로 바꾸는 순수 함수.

public enum SceneBuilder {

    // MARK: 털 무늬

    /// 종은 하네스, 털 무늬는 모델이다(시안 HARNESS·COAT). 모델 ID의 부분 문자열로 맞춘다.
    public static func coat(harness: Harness, model: String?) -> Coat {
        let m = model?.lowercased() ?? ""
        switch harness {
        case .codex: return ["mini", "nano"].contains(where: m.contains) ? .dogSpot : .beagle
        case .agy: return ["flash", "lite"].contains(where: m.contains) ? .frogSpot : .frog
        default:
            for (key, c) in [("fable", Coat.tuxedo), ("opus", .calico), ("sonnet", .tabby), ("haiku", .white)] where m.contains(key) { return c }
            return .catGray
        }
    }

    // MARK: 급한 일

    /// 지반 우선순위: 결정·입력 대기 > 단위 막힘 > 환경·한도 > 사용자 정지.
    enum Urgent {
        case decision(Decision)
        case unitBlocked(UnitState, Halt)
        case environment(text: String, agent: Terminal?, halt: Halt?)
        case input(Terminal)
        case userStop(Halt)

        /// 지붕과 건물 등에 쓰는 짧은 이름.
        var label: String {
            switch self {
            case .decision: return HaltClass.decision.label
            case .unitBlocked: return HaltClass.unitBlocked.label
            case .environment(_, _, let h): return h.map { envLabel($0.reason) } ?? HaltClass.environment.label
            case .input: return "입력 대기"
            case .userStop: return HaltClass.userStop.label
            }
        }

        /// 목록의 멈춤 꼬리표. 분류 이름 그대로 쓴다.
        var tag: String {
            switch self {
            case .environment: return HaltClass.environment.label
            default: return label
            }
        }

        /// 당신 차례인가. 사용자 정지는 이미 사용자가 한 일이라 분홍이 아니다.
        var turn: Bool { if case .userStop = self { return false } else { return true } }
    }

    static func urgent(_ p: Project) -> Urgent? {
        let plan = p.hasEvents ? p.activePlan : nil
        // 결정은 보는 계획만이 아니라 모든 계획에서 모은다. 단위를 멈춘 결정을 먼저 보인다.
        let open = p.hasEvents ? p.openDecisions : [], halts = p.hasEvents ? p.decisionHalts : []
        let linked = Set(halts.compactMap(\.halt.decision))
        if let d = open.first(where: { linked.contains($0.id) }) ?? open.first { return .decision(d) }
        let waiting = p.agents.filter { $0.status == .blocked }
        if let terminal = waiting.first(where: { $0.question != nil }) ?? waiting.first { return .input(terminal) }
        // 결정 요청 기록 없이 멈춤만 있으면(손으로 쓴 halt) 질문을 모른다.
        if let (pl, h) = halts.first {
            let owner = p.plans.first { $0.plan == pl }?.units.first { $0.id == h.unit }?.owner
            return .decision(Decision(id: "halt:\(h.unit ?? pl)", question: "결정이 필요합니다", blocks: h.unit.map { [$0] } ?? [], asker: owner, ts: h.ts))
        }
        if let plan, let h = plan.allHalts.first(where: { $0.kind == .unitBlocked }),
           let u = plan.units.first(where: { $0.id == (h.unit ?? String(h.reason.drop { $0 != ":" }.dropFirst())) }) {
            return .unitBlocked(u, h)
        }
        let errAgent = p.agents.first { $0.status == .error }
        if let h = plan?.allHalts.first(where: { $0.kind == .environment }) {
            let who = errAgent.map { "\(name($0))\(josa(name($0), "이", "가")) 멈췄습니다" } ?? "멈췄습니다"
            let l = envLabel(h.reason)
            return .environment(text: "\(l)\(josa(l, "으로", "로")) \(who)", agent: errAgent, halt: h)
        }
        if let t = errAgent { return .environment(text: "\(name(t))\(josa(name(t), "이", "가")) 오류로 멈췄습니다", agent: t, halt: nil) }
        if let h = plan?.allHalts.first(where: { $0.kind == .userStop }) ?? plan.flatMap(appliedStop) { return .userStop(h) }
        return nil
    }

    /// 적용된 열린 정지·중단 지시. 즉시 중단은 halt 기록 없이 적용만 적히므로 지시에서 멈춤을 만든다.
    static func appliedStop(_ plan: PlanState) -> Halt? {
        plan.openStops.last { $0.status == .applied }.map { Halt(reason: $0.kind.rawValue, unit: nil, ts: $0.ts, directive: $0.id) }
    }

    static func envLabel(_ reason: String) -> String { reason.hasPrefix("limit") ? "한도 초과" : HaltClass.environment.label }

    // MARK: 캐릭터

    /// 탭 이름이 "1"처럼 숫자뿐이면 누구인지 알 수 없다. 그때는 스페이스 이름을 앞에 붙인다.
    public static func name(_ t: Terminal) -> String {
        let tab = t.tabName
        if tab.isEmpty { return t.address }
        guard tab.allSatisfy(\.isNumber) else { return tab }
        let both = t.location.replacingOccurrences(of: " / ", with: " ")
        return both == tab ? t.address : both
    }

    /// 말풍선은 한 줄 요약이다. 긴 상태 문구는 장면을 가리므로 자른다.
    static func brief(_ s: String, max: Int = 18) -> String { s.count > max ? s.prefix(max) + "…" : s }

    public static func actors(_ p: Project) -> [SceneActor] {
        let plan = p.hasEvents ? p.activePlan : nil
        var askers = Set((p.hasEvents ? p.openDecisions : []).compactMap { $0.asker?.terminal })
        if case .decision(let d)? = urgent(p), let t = d.asker?.terminal { askers.insert(t) }
        let stopped = plan.map { $0.allHalts.contains { $0.kind == .userStop } || appliedStop($0) != nil } ?? false
        return p.agents.map { t in
            let info = plan?.actors[t.address]
            let owns = plan?.units.contains { $0.owner?.terminal == t.address && $0.phase != .done } ?? false
            var pose: Pose, text: String
            if askers.contains(t.address) { pose = .ask; text = "결정 대기" }
            else {
                switch t.status {
                case .blocked: pose = .ask; text = "입력 대기"
                case .error: pose = .error; text = "오류"
                case .working: pose = .work; text = "작업 중"
                // 맡은 단위가 있으면 그 자리에 서서 기다린다. 없으면 소파에서 존다.
                case .idle: pose = owns ? .wait : .sleep; text = "쉬는 중"
                case .done: pose = .done; text = "완료"
                case .unknown: pose = .wait; text = "상태 모름"
                }
                if stopped && (pose == .sleep || pose == .wait) { pose = .stopped; text = HaltClass.userStop.label }
            }
            return SceneActor(id: t.address, name: name(t), harness: t.harness, model: info?.model, effort: info?.effort, status: t.status,
                              coat: coat(harness: t.harness, model: info?.model), pose: pose, spot: .sofa(0), carry: nil, stateText: text, statusText: t.statusText)
        }
    }

    // MARK: 사무실

    public static func office(_ world: World, project pi: Int, night: Bool) -> OfficeView {
        let p = world.projects[pi]
        let plan = p.hasEvents ? p.activePlan : nil
        let units = plan?.units ?? []
        let all = actors(p)

        // 자리: 결정·입력 대기는 벨, 졸면 소파, 맡은 단위가 있으면 그 단계의 장소, 일하면 빈 책상, 그 밖은 소파.
        var freeDesks = Array(OfficeLayout.desks.indices), freeSofa = Array(0..<OfficeLayout.sofaSeats)
        var bellFree = true, testFree = true, uiFree = true
        var seated: [SceneActor] = [], deskOf: [String: Int] = [:]
        for var a in all {
            let owned = units.first { $0.owner?.terminal == a.id && [.build, .verify, .review].contains($0.phase) }
            var spot: Spot?
            if a.pose == .ask && bellFree { spot = .bell; bellFree = false }
            else if a.pose != .sleep, let u = owned {
                switch u.phase {
                case .build where !freeDesks.isEmpty: let d = freeDesks.removeFirst(); spot = .desk(d); deskOf[u.id] = d
                case .verify where testFree: spot = .test; testFree = false
                case .review where uiFree: spot = .ui; uiFree = false
                default: break
                }
            }
            // 사용자 정지면 서서 멈춘 담당자도 책상 앞에 둔다(시안: 계획자가 책상에서 멈춤 표시).
            if spot == nil, a.pose == .work || a.pose == .stopped, !freeDesks.isEmpty { spot = .desk(freeDesks.removeFirst()) }
            if spot == nil, !freeSofa.isEmpty { spot = .sofa(freeSofa.removeFirst()) }
            guard let s = spot else { continue }
            a.spot = s; seated.append(a)
        }

        // 상자: 장소가 단계다. 선반은 칸 수까지만(대기는 번호가 작은 것부터, 완료는 최근 것부터).
        var boxes: [SceneBox] = []
        func add(_ u: UnitState, _ place: BoxPlace) {
            boxes.append(SceneBox(id: u.id, number: u.number, title: u.title, phase: u.phase, place: place, blocked: u.halt?.kind == .unitBlocked))
        }
        let queued = units.filter { $0.phase == .queued }.sorted { ($0.number ?? 0) < ($1.number ?? 0) }
        for (i, u) in queued.prefix(OfficeLayout.shelfSlots).enumerated() { add(u, .backlog(slot: i)) }
        let done = units.filter { $0.phase == .done }.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
            .prefix(OfficeLayout.shelfSlots).sorted { ($0.number ?? 0) < ($1.number ?? 0) }
        for (i, u) in done.enumerated() { add(u, .done(slot: i)) }
        var boxDesks = Set(deskOf.values)
        for u in units where u.phase == .build {
            if let d = deskOf[u.id] { add(u, .desk(d)) }
            else if let d = OfficeLayout.desks.indices.first(where: { !boxDesks.contains($0) }) { boxDesks.insert(d); add(u, .desk(d)) }
        }
        if let u = units.first(where: { $0.phase == .verify }) { add(u, .test) }
        if let u = units.first(where: { $0.phase == .review }) { add(u, .ui) }

        // 시험대 등: 막힘이나 실패는 빨강, 통과는 초록, 결과 전에 담당자가 일하면 노랑.
        var lamp = Lamp.off
        if let u = units.first(where: { $0.phase == .verify }) {
            if u.halt?.kind == .unitBlocked { lamp = .fail }
            else if let e = u.latest(.cmd) { lamp = e.pass ? .ok : .fail }
            else if all.contains(where: { $0.id == u.owner?.terminal && $0.pose == .work }) { lamp = .run }
        }
        let halts = plan?.allHalts ?? []
        let pendingStop = !(plan?.openStops.isEmpty ?? true)

        let blockedOwners = Set(units.filter { $0.halt?.kind == .unitBlocked }.compactMap { $0.owner?.terminal })
        var bubbles: [Bubble] = [], hits: [HitTarget] = []
        for a in seated {
            let p = a.spot.point, b = spriteBounds(x: p.x, y: p.y, coat: a.coat, pose: a.pose)
            hits.append(HitTarget(kind: .actor(a.id), rect: CGRect(x: b.bx - 2, y: b.by - 2, width: 16, height: b.bh + 4),
                                  label: "\(a.name), \(a.model ?? a.harness.rawValue), \(a.stateText)"))
            // 주의 상태에는 말풍선을 쓰지 않는다. 글은 지반에 적는다.
            if let t = a.statusText, !t.isEmpty, ![.ask, .error, .stopped].contains(a.pose), !blockedOwners.contains(a.id) {
                bubbles.append(Bubble(text: brief(t), actorID: a.id, anchor: CGPoint(x: b.bx + 6, y: b.by - 3)))
            }
        }
        for b in boxes {
            let p = b.place.point
            hits.append(HitTarget(kind: .box(b.id), rect: CGRect(x: Double(p.x) - 0.5, y: Double(p.y - 2), width: 12, height: 12),
                                  label: "\(b.id)\(b.title.map { " " + $0 } ?? ""), \(b.phase.label) 단계\(b.blocked ? ", 단위 막힘" : "")"))
        }

        let scene = OfficeScene(
            night: night, actors: seated, boxes: boxes, lamp: lamp, bell: { if case .decision? = urgent(p) { true } else { false } }(),
            stopSign: halts.contains { $0.kind == .userStop } || pendingStop, officeError: halts.contains { $0.kind == .environment },
            hiddenActors: all.count - seated.count, hiddenBoxes: units.count - boxes.count,
            labels: OfficeLayout.rail.map { WallLabel(text: $0.0, style: .stage, rect: CGRect(x: $0.1, y: 22, width: 0, height: 0)) },
            bubbles: bubbles, hits: hits)
        return OfficeView(scene: scene, roof: roof(world, office: pi), ground: officeGround(world, pi, all), list: officeList(p, all))
    }

    static func roof(_ world: World, office pi: Int) -> RoofModel {
        let p = world.projects[pi], plan = p.hasEvents ? p.activePlan : nil
        let total = plan?.units.count ?? 0, done = plan?.doneCount ?? 0
        let others = world.projects.indices.filter { $0 != pi }.compactMap { i in urgent(world.projects[i]).flatMap { $0.turn ? (i, $0) : nil } }
        // 다른 층 중 가장 급한 것 하나를 넓게, 건수는 좁게 적는다.
        let top = others.min { rank($0.1) < rank($1.1) }
        return RoofModel(title: p.name, cells: (0..<total).map { $0 < done }, count: plan == nil ? nil : "완료 \(done)/\(total)",
                         alert: top.map { RoofModel.Alert(floor: $0.0, long: "\(world.projects[$0.0].name) 층 \($0.1.label)", short: "다른 층 \(others.count)건") },
                         isDemo: world.projects.contains { $0.isDemo })
    }

    static func rank(_ u: Urgent) -> Int {
        switch u { case .decision(let d): d.id.hasPrefix("halt:") ? 3 : 0
        case .input(let t): t.question == nil ? 2 : 1
        case .unitBlocked: 4; case .environment: 5; case .userStop: 6 }
    }

    static func face(_ all: [SceneActor], _ id: String?) -> GroundIcon? {
        all.first { $0.id == id }.map { .face($0.coat, $0.pose) }
    }

    static func ownerName(_ p: Project, _ u: UnitState) -> String {
        guard let t = u.owner?.terminal else { return "담당자" }
        return p.terminals.first { $0.address == t }.map(name) ?? t
    }

    static func result(_ e: Evidence) -> String { (e.pass ? "통과" : "실패") + (e.reason.map { " " + $0 } ?? "") }

    static func blockedDetail(_ u: UnitState, _ h: Halt) -> String {
        u.latestEvidence.map { "\($0.kind.label) \(result($0))" } ?? "멈춘 사유: \(h.reason)"
    }

    static func stopDetail(_ h: Halt) -> String {
        h.reason == "interrupt" ? "즉시 중단을 적용했습니다" : "단위 후 정지를 적용했습니다"
    }

    public static func projectGround(_ world: World, at index: Int) -> GroundModel {
        officeGround(world, index, actors(world.projects[index]))
    }

    static func officeGround(_ world: World, _ pi: Int, _ all: [SceneActor]) -> GroundModel {
        let p = world.projects[pi], plan = p.hasEvents ? p.activePlan : nil
        switch urgent(p) {
        case .decision(let d):
            let blocks = d.blocks.enumerated().map { $0.offset < d.blocks.count - 1 ? $0.element + josa($0.element, "과", "와") : $0.element }.joined(separator: " ")
            let other = decisionPlan(p, d).map { "\($0) 계획의 " } ?? ""
            let small = "결정 대기" + (blocks.isEmpty ? "" : ". \(other)\(blocks)\(josa(blocks, "이", "가")) 이 답을 기다립니다")
            return GroundModel(turn: true, floor: pi, icon: face(all, d.asker?.terminal) ?? .bell, title: d.question, detail: small, buttons: answerButtons(d))
        case .unitBlocked(let u, let h):
            let who = ownerName(p, u)
            return GroundModel(turn: true, floor: pi, icon: .box(number: u.number, done: false), title: "\(u.id) 단위 막힘",
                               detail: "\(blockedDetail(u, h)). \(who)\(josa(who, "이", "가")) 멈췄습니다",
                               buttons: u.owner?.terminal.map { [GroundButton("\(who)에게 메시지", .message(terminal: $0), primary: true)] } ?? [])
        case .environment(let text, let t, let h):
            return GroundModel(turn: true, floor: pi, icon: face(all, t?.address) ?? .bell, title: text,
                               detail: h.map { "환경·한도. \($0.reason). \(resumeHint(p, $0))" } ?? (t?.statusText ?? "환경·한도"), buttons: [])
        case .input(let t):
            let n = name(t)
            if let q = t.question {
                let b = choiceButtons(terminal: t.address, q)
                return GroundModel(turn: true, floor: pi, icon: face(all, t.address) ?? .bell, title: q.text,
                                   detail: "\(n)\(josa(n, "이", "가")) 답을 기다립니다", buttons: b)
            }
            return GroundModel(turn: true, floor: pi, icon: face(all, t.address) ?? .bell, title: "\(n)\(josa(n, "이", "가")) 터미널에서 입력을 기다립니다",
                               detail: t.statusText ?? t.location, buttons: [])
        case .userStop(let h):
            let tail = h.reason == "interrupt" ? ". 미완료 변경은 지우지 않았습니다" : ". 다음 단위를 시작하지 않습니다"
            let can = resumable(plan, h)
            return GroundModel(turn: false, floor: pi, icon: .stop, title: "사용자 정지 상태입니다", detail: stopDetail(h) + (can ? tail : ". " + resumeHint(p, h)),
                               buttons: can ? [GroundButton("계속", .resume, primary: true)] : [])
        case nil:
            let elseAlert = roof(world, office: pi).alert != nil
            // 여기 오면 열린 정지·중단은 모두 접수만 된 것이다(적용되면 사용자 정지).
            let dirs = plan?.openStops ?? []
            let stopReq = dirs.contains { $0.kind == .stopAfter }
            let active = plan?.units.first { [.build, .verify, .review].contains($0.phase) }
            let small = dirs.contains { $0.kind == .interrupt } ? "즉시 중단을 접수했습니다"
                : stopReq ? "이 단위를 마치면 멈춥니다"
                : active.map { "\($0.id)\($0.title.map { " " + $0 } ?? ""): \($0.phase.label) 단계" } ?? "진행 중인 단위가 없습니다"
            // 기록이 없는 프로젝트에는 단위가 없으므로 정지 버튼을 두지 않는다.
            let btns = plan == nil ? [] : [GroundButton(stopReq ? "정지 접수됨" : "단위 후 정지", .stopAfter, disabled: stopReq), GroundButton("중단", .interrupt)]
            return GroundModel(turn: false, floor: pi, icon: .bell, title: elseAlert ? "이 층은 조용합니다" : "조용합니다. " + calm(all), detail: small, buttons: btns)
        }
    }

    /// 결정으로 멈춘 단위가 보는 계획이 아닌 계획에 있으면 그 계획 값. 같은 계획이거나 모르면 nil.
    static func decisionPlan(_ p: Project, _ d: Decision) -> String? {
        let at = p.decisionHalts.first { $0.halt.decision == d.id || "halt:\($0.halt.unit ?? $0.plan)" == d.id }?.plan
            ?? p.plans.first { pl in pl.decisions.contains { $0.id == d.id } && pl.units.contains { d.blocks.contains($0.id) } }?.plan
        guard let at, at != p.activePlan?.plan else { return nil }
        return at
    }

    /// "계속"(direct resume)은 지시로 건 멈춤만 푼다. 지시 연결이 있거나 열린 정지·중단 지시가 있을 때만 버튼을 둔다.
    static func resumable(_ plan: PlanState?, _ h: Halt) -> Bool {
        h.directive != nil || !(plan?.openStops.isEmpty ?? true)
    }

    /// 앱이 풀 수 없는 멈춤의 안내. 단위 담당자, 없으면 첫 에이전트의 터미널.
    static func resumeHint(_ p: Project, _ h: Halt) -> String {
        let t = p.plans.lazy.compactMap { $0.units.first { $0.id == h.unit }?.owner?.terminal }.first ?? p.agents.first?.address
        return "\(t.map { "터미널 \($0)" } ?? "터미널")에서 계속하세요"
    }

    /// 결정 답 버튼. 선택지가 있으면 선택지를, 없으면 추천안을 버튼으로 둔다. 추천안 버튼이 주된 버튼이다.
    /// 선택지가 길면 기존 자유 입력과 모든 원래 답을 함께 제공한다.
    static func answerButtons(_ d: Decision) -> [GroundButton] {
        let reply = GroundButton("다르게 답하기", .reply(decision: d.id))
        func pick(_ s: String) -> GroundButton { GroundButton(s, .answer(decision: d.id, text: s), primary: s == d.recommendation) }
        guard !d.options.isEmpty else {
            return d.recommendation.map { [pick($0), reply] } ?? [GroundButton("답하기", .reply(decision: d.id), primary: true)]
        }
        if fits(d.options) { return d.options.map(pick) }
        return d.options.map(pick) + [reply]
    }

    /// 질문 화면의 번호를 보존한다. 패널은 남은 선택지를 기본 메뉴에 담는다.
    public static func choiceButtons(terminal: String, _ q: ScreenQuestion) -> [GroundButton] {
        q.options.map { GroundButton($0.label, .choose(terminal: terminal, number: $0.number)) }
    }

    /// 지반 버튼 줄의 폭 한도(pt). 지반 240에서 글 시작(40), 오른쪽 여백 6, 닫기 버튼 자리(24 + 간격 6)를 뺀 값이다.
    /// 버튼 하나는 Jua 12 글자 폭 + 20(최소 32)이고 버튼 사이는 6이다(Parts.swift GroundView). 합에 간격 하나가 더 붙어 6을 더한다.
    static let buttonRowMax: Double = 240 - 40 - 6 - 30 + 6

    static func fits(_ labels: [String]) -> Bool {
        labels.reduce(0) { $0 + buttonWidth($1) + 6 } <= buttonRowMax
    }

    static func buttonWidth(_ s: String) -> Double {
        let font = CTFontCreateWithName(Fonts.jua as CFString, 12, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        return max(32, ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 20)
    }

    private static let NUM = ["", "하나", "둘", "셋", "넷", "다섯"]

    /// 시안의 calm: 일하는 수와 쉬는 수.
    static func calm(_ list: [SceneActor]) -> String {
        let w = list.filter { $0.pose == .work }.count, r = list.count - w
        func n(_ k: Int) -> String { k < NUM.count ? NUM[k] : "\(k)명" }
        if w == 0 { return "모두 쉬고 있습니다" }
        let subj = n(w) + josa(n(w), "이", "가")
        if r == 0 { return subj + " 일하는 중입니다" }
        return subj + " 일하고 " + n(r) + josa(n(r), "은", "는") + " 쉽니다"
    }

    static func haltTag(_ text: String) -> ListTag { ListTag(text: text, style: text == HaltClass.userStop.label ? .halt : .turn) }

    static func officeList(_ p: Project, _ all: [SceneActor]) -> ListModel {
        let plan = p.hasEvents ? p.activePlan : nil
        let agents = all.map { a in
            ListRow(face: FloorAgent(coat: a.coat, pose: a.pose), title: a.name,
                    subtitle: a.stateText + (a.statusText.map { ". " + $0 } ?? ""), tags: [],
                    meta: [a.harness.rawValue, a.model, a.effort.map { "effort " + $0 }].compactMap { $0 }.joined(separator: ", "))
        }
        var sections = [ListSection(title: "담당자", wide: false, rows: agents)]
        guard let plan else { return ListModel(sections: sections) }
        let planStop = plan.halts.first { $0.kind == .userStop } ?? appliedStop(plan)
        let units = plan.units.map { u -> ListRow in
            var why: String?
            if u.phase != .done {
                if let h = u.halt { why = h.kind.label }
                else if planStop != nil { why = HaltClass.userStop.label }
                else if p.openDecisions.contains(where: { $0.blocks.contains(u.id) }) { why = HaltClass.decision.label }
            }
            // 값이 있는 증거만 종류 순서대로 적는다.
            let ev = EvidenceKind.allCases.compactMap { k in u.latest(k).map { "\(k.label) \(result($0))" } }.joined(separator: ", ")
            return ListRow(face: nil, title: u.id, subtitle: u.title, tags: [ListTag(text: u.phase.label, style: .plain)] + (why.map { [haltTag($0)] } ?? []),
                           meta: ev.isEmpty ? nil : ev)
        }
        sections.append(ListSection(title: "단위", wide: false, rows: units))
        // 열린 결정은 계획과 상관없이 모두 적는다. 다른 계획의 결정은 계획 값을 붙인다.
        let open = p.openDecisions
        if !open.isEmpty {
            sections.append(ListSection(title: "열린 결정", wide: true, rows: open.map { d in
                ListRow(face: nil, title: d.id, subtitle: d.question, tags: [ListTag(text: HaltClass.decision.label, style: .turn)],
                        meta: ([decisionPlan(p, d).map { "\($0) 계획" }, d.blocks.isEmpty ? nil : d.blocks.joined(separator: ", ") + " 멈춤", d.recommendation.map { "추천: " + $0 }]
                            .compactMap { $0 }.joined(separator: ". ")).nilIfEmpty)
            }))
        }
        let dirs = plan.directives.reversed().prefix(8).map { d in
            ListRow(face: nil, title: d.kind.label, subtitle: d.text, tags: [ListTag(text: d.closed ? "풀림" : d.status.label, style: .plain)], meta: d.reason)
        }
        sections.append(ListSection(title: "지시 기록", wide: true, rows: dirs.isEmpty ? [ListRow(face: nil, title: "아직 보낸 지시가 없습니다", subtitle: nil, tags: [], meta: nil)] : Array(dirs)))
        return ListModel(sections: sections)
    }

    // MARK: 건물

    /// firstFloor는 보이는 첫 층이다. 층이 한 화면을 넘을 때만 쓴다.
    public static func building(_ world: World, firstFloor: Int = 0, night: Bool) -> BuildingView {
        let n = world.projects.count, vis = BuildingLayout.visibleFloors
        let first = max(0, min(firstFloor, n - vis))
        let range = first..<min(n, first + vis)
        var floors: [BuildingFloor] = [], labels: [WallLabel] = [], hits: [HitTarget] = []
        for (k, i) in range.enumerated() {
            let f = floor(world.projects[i], i)
            let y = BuildingLayout.floorY + k * BuildingLayout.floorH
            floors.append(f)
            labels.append(WallLabel(text: f.name, style: .floorName, rect: CGRect(x: 22, y: y + 2, width: 62, height: 11)))
            let why = urgent(world.projects[i]).map { ", " + $0.label } ?? ""
            hits.append(HitTarget(kind: .floor(i), rect: CGRect(x: 20, y: y, width: 196, height: 21), label: "\(f.name) 층, 완료 \(f.done)/\(f.total)\(why)"))
        }
        let scene = BuildingScene(night: night, floors: floors, firstFloor: first, moreAbove: first > 0, moreBelow: range.upperBound < n, labels: labels, hits: hits)
        let roof = RoofModel(title: "전체 프로젝트", cells: [], count: "\(n)개 층", alert: nil, isDemo: world.projects.contains { $0.isDemo })
        return BuildingView(scene: scene, roof: roof, ground: buildingGround(world), list: buildingList(world))
    }

    static func floor(_ p: Project, _ i: Int) -> BuildingFloor {
        let plan = p.hasEvents ? p.activePlan : nil
        let alert: FloorAlert? = switch urgent(p) {
        case .decision, .input: .ask
        case .unitBlocked, .environment: .error
        case .userStop, nil: nil
        }
        return BuildingFloor(index: i, name: p.name, agents: actors(p).prefix(BuildingLayout.agentsPerFloor).map { FloorAgent(coat: $0.coat, pose: $0.pose) },
                             done: plan?.doneCount ?? 0, total: plan?.units.count ?? 0, alert: alert)
    }

    /// 모든 층 중에서 가장 급한 일 하나. 같으면 위층이 먼저다.
    public static func buildingGround(_ world: World) -> GroundModel {
        let all = world.projects.indices.compactMap { i in urgent(world.projects[i]).map { (i, $0) } }
        guard let (i, u) = all.min(by: { rank($0.1) < rank($1.1) }) else {
            return GroundModel(turn: false, floor: nil, icon: .building, title: world.projects.isEmpty ? "아직 열린 층이 없어요" : "조용합니다. 나설 일이 없습니다",
                               detail: world.projects.isEmpty ? "에이전트가 있는 프로젝트가 여기에 표시됩니다" : "층 \(world.projects.count)개가 일하거나 쉬는 중입니다", buttons: [])
        }
        let p = world.projects[i], people = actors(p), go = [GroundButton("층으로 가기", .enterFloor(i), primary: true)]
        let title = "\(p.name) 층: \(u.label)"
        switch u {
        case .decision(let d):
            return GroundModel(turn: true, floor: i, icon: face(people, d.asker?.terminal) ?? .bell, title: title, detail: d.question, buttons: go)
        case .unitBlocked(let unit, let h):
            return GroundModel(turn: true, floor: i, icon: .box(number: unit.number, done: false), title: title, detail: "\(unit.id) \(blockedDetail(unit, h))", buttons: go)
        case .environment(let text, let t, _):
            return GroundModel(turn: true, floor: i, icon: face(people, t?.address) ?? .bell, title: "\(p.name) 층: \(HaltClass.environment.label)", detail: text, buttons: go)
        case .input(let t):
            return GroundModel(turn: true, floor: i, icon: face(people, t.address) ?? .bell, title: title, detail: inputDetail(t), buttons: go)
        case .userStop(let h):
            let can = resumable(p.hasEvents ? p.activePlan : nil, h)
            return GroundModel(turn: false, floor: i, icon: .stop, title: title, detail: stopDetail(h) + (can ? "" : ". " + resumeHint(p, h)),
                               buttons: can ? [GroundButton("계속", .resume, primary: true)] : [])
        }
    }

    static func inputDetail(_ terminal: Terminal) -> String {
        if let question = terminal.question { return question.text }
        let n = name(terminal)
        if let status = terminal.statusText, !status.isEmpty { return n + " · " + status }
        return "\(n)\(josa(n, "이", "가")) 터미널에서 입력을 기다립니다"
    }

    static func buildingList(_ world: World) -> ListModel {
        let rows = world.projects.enumerated().map { i, p -> ListRow in
            let f = floor(p, i), u = urgent(p), people = actors(p)
            let text: String
            if case .environment(let t, _, _) = u { text = t }
            else if p.hasEvents && f.total > 0 && f.done == f.total { text = "모든 단위가 완료입니다" }
            else { text = calm(people) }
            return ListRow(face: nil, title: p.name, subtitle: nil, tags: [ListTag(text: "완료 \(f.done)/\(f.total)", style: .plain)] + (u.map { [haltTag($0.tag)] } ?? []),
                           meta: text)
        }
        return ListModel(sections: [ListSection(title: "프로젝트", wide: true, rows: rows)])
    }

    // MARK: 조사

    /// 받침이 있으면 a, 없으면 b. "으로/로"는 ㄹ 받침도 "로"다.
    static func josa(_ word: String, _ a: String, _ b: String) -> String {
        guard let last = word.unicodeScalars.last else { return b }
        var final = false, rieul = false
        if (0xAC00...0xD7A3).contains(last.value) {
            let jong = (last.value - 0xAC00) % 28
            final = jong != 0; rieul = jong == 8
        } else if let d = Int(String(last)) {
            final = [0, 1, 3, 6, 7, 8].contains(d); rieul = [1, 7, 8].contains(d)
        } else {
            final = "lmnLMN".unicodeScalars.contains(last); rieul = "lL".unicodeScalars.contains(last)
        }
        if a == "으로" && rieul { return b }
        return final ? a : b
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
