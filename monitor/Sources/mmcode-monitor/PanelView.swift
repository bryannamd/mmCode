import AppKit
import MonitorCore
import MonitorScene

/// 프로젝트 개요, 담당자, 작업 공간과 기록을 표시하는 패널. 화면 상태(보기, 선택, 보이는 층)를 들고 SceneBuilder의 값을 세 층에 나눠 준다.
/// 결정 답과 지시는 PhaseClient(phase.sh answer·direct)로 보낸다. 메시지와 객관식 답은 HcClient.write(send·keys)로 터미널에 직접 보낸다.
/// 예시 자료와 화면 찍기에서는 무엇도 보내지 않는다.
final class PanelView: NSView {
    enum Mode { case office, building, list }
    /// 지반의 입력칸. 다르게 답하기와 메시지.
    enum Form: Equatable { case reply(decision: String, question: String), message(terminal: String, name: String) }

    static let size = CGSize(width: 380, height: 360)
    static let mapHeight = size.width * 108 / 240
    let roof = RoofView(frame: CGRect(x: 0, y: 0, width: size.width, height: RoofView.height))
    let ground = GroundView(frame: CGRect(x: 0, y: RoofView.height, width: size.width, height: 84))
    let scene = SceneView(frame: CGRect(x: 0, y: 0, width: size.width, height: mapHeight))
    let activity = ActivityPane(frame: CGRect(x: 0, y: 0, width: size.width, height: 240))
    private(set) var showsMap = false
    private var people: [SceneActor] = []
    private var summaries: [ProjectSummary] = []
    let list = ListPane(frame: CGRect(x: 0, y: size.height - 108, width: size.width, height: 108))
    var onSceneVisibilityChange: () -> Void = {}
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var world = World()
    var demo = false, hcMissing = false, hcDown = false, loaded = false
    var mode = Mode.building, back = Mode.building
    var officeRoot: String?
    var firstFloor = 0
    var selection: HitTarget.Kind?
    var notice: String?
    private var noticeRoot: String?
    var fixedNight: Bool?
    var frameNo = 0
    var onFocus: (String?) -> Void = { _ in }
    var onClose: () -> Void = {}

    private var office: OfficeView?, building: BuildingView?
    private var said: [String: (text: String, at: Date)] = [:]
    private var bubbleTimer: Timer?
    private var focused: String?
    /// 입력칸이나 중단 확인이 걸린 프로젝트 루트.
    private var form: (root: String, kind: Form)?
    private var confirmStop: String?
    private var sending = false
    /// 스냅숏(화면 밖 찍기)이면 true. 그때는 무엇도 보내지 않는다.
    var noSend = false
    /// 보낸 뒤 그 기록을 다시 읽기 전까지 같은 버튼을 막는다(지시 종류나 결정 ID). 다음 갱신이나 5초 뒤에 푼다.
    private var sent = Set<String>()
    /// 찾은 phase.sh. 보내기가 사용 오류나 실행 실패로 끝나면 비우고 다시 찾는다. 못 찾은 동안은 그릴 때마다 찾는다.
    private var phaseFound: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .aqua)
        [roof, ground, scene, list, activity].forEach(addSubview)
        list.isHidden = true
        roof.building.onPress = { [unowned self] in go(.building) }
        roof.map.onPress = { [unowned self] in
            if mode == .list { mode = back }
            showsMap.toggle()
            reload()
        }
        activity.select = { [unowned self] id in
            if office != nil { selectTarget(.actor(id)) }
            else if let i = world.projects.firstIndex(where: { $0.root == id }) { enter(i) }
        }
        roof.list.onPress = { [unowned self] in go(mode == .list ? back : .list) }
        scene.overlay.onEmptyClick = { [unowned self] in if selection != nil || notice != nil { selection = nil; notice = nil; form = nil; confirmStop = nil; reload() } }
        scene.onScroll = { [unowned self] d in scrollFloors(d) }
        setAccessibilityLabel("mmCode 모니터 패널")
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var night: Bool { fixedNight ?? { $0 < 7 || $0 >= 18 }(Calendar.current.component(.hour, from: Date())) }
    var officeIndex: Int? { officeRoot.flatMap { r in world.projects.firstIndex { $0.root == r } } }

    // MARK: 이동

    func openOverview() {
        if form == nil && confirmStop == nil && !sending { go(.building) }
        else { reload() }
    }

    func go(_ m: Mode) {
        if m == .office && officeIndex == nil { return }
        if m != .list { back = m }
        showsMap = false
        mode = m; selection = nil; notice = nil; form = nil; confirmStop = nil
        reload()
    }

    func enter(_ i: Int) {
        guard world.projects.indices.contains(i) else { return }
        officeRoot = world.projects[i].root
        go(.office)
    }

    func selectTarget(_ kind: HitTarget.Kind) {
        selection = selection == kind ? nil : kind
        notice = nil; form = nil; confirmStop = nil
        reload()
    }

    func scrollFloors(_ d: Int) {
        guard mode == .building else { return }
        let n = max(0, world.projects.count - BuildingLayout.visibleFloors), f = max(0, min(n, firstFloor + d))
        if f != firstFloor { firstFloor = f; reload() }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: escape()
        case 126 where !activity.isHidden: activity.move(-1)
        case 125 where !activity.isHidden: activity.move(1)
        case 126 where mode == .building: scrollFloors(-1)
        case 125 where mode == .building: scrollFloors(1)
        case 125, 126, 121, 116:
            // `where`는 마지막 패턴에만 붙는다. 그래서 보기를 안에서 따로 확인한다.
            guard mode == .list else { return super.keyDown(with: event) }
            window?.makeFirstResponder(list.doc); list.doc.keyDown(with: event)
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { escape() }

    /// Esc: 입력칸·확인, 선택이나 안내를 먼저 풀고, 없으면 패널을 닫는다.
    func escape() {
        if form != nil || confirmStop != nil { form = nil; confirmStop = nil; reload() }
        else if selection != nil || notice != nil { selection = nil; notice = nil; reload(); window?.makeFirstResponder(self) } else { onClose() }
    }

    // MARK: 갱신

    /// 자료가 바뀌면 부른다. 패널이 닫혀 있어도 말풍선의 바뀐 시각만은 적어 둔다.
    func noteSaid() {
        guard let i = officeIndex else { return }
        let now = Date()
        for b in SceneBuilder.office(world, project: i, night: false).scene.bubbles where said[b.actorID]?.text != b.text { said[b.actorID] = (b.text, now) }
    }

    func reload() {
        let n = night
        if mode != .building, back == .office, let i = officeIndex {
            office = SceneBuilder.office(world, project: i, night: n); building = nil
            people = SceneBuilder.actors(world.projects[i])
        } else {
            if mode == .office { mode = .building }
            back = .building
            office = nil; people = []
            summaries = world.projects.map(SceneBuilder.projectSummary)
            let b = SceneBuilder.building(world, firstFloor: firstFloor, night: n)
            building = b; firstFloor = b.scene.firstFloor
        }
        // 사무실로 보는 프로젝트의 기록 파일만 지켜본다.
        let urgentRoot = building.flatMap { $0.ground.turn ? $0.ground.floor : nil }.map { world.projects[$0].root }
        let f = form?.root ?? (office == nil ? urgentRoot : officeRoot)
        if f != focused { focused = f; onFocus(f) }
        if let o = office, let s = selection {
            let ok: Bool = switch s {
            case .actor(let id): people.contains { $0.id == id }
            case .box(let id): o.scene.boxes.contains { $0.id == id }
            case .floor: false
            }
            if !ok { selection = nil }
        } else { selection = nil }

        var header = office?.roof ?? building!.roof
        if !loaded { header.count = nil }
        roof.update(header, office: office != nil, listOn: mode == .list, mapOn: showsMap)
        let targetRoot = form?.root ?? (office != nil ? officeRoot : building?.ground.floor.map { world.projects[$0].root })
        ground.update(groundSpec(), project: targetRoot)
        let y = ground.frame.maxY
        let hasData = loaded && !hcDown && !hcMissing
        let isRecord = mode == .list
        let wasHidden = scene.isHidden
        scene.isHidden = !hasData || !showsMap || isRecord
        if wasHidden != scene.isHidden { onSceneVisibilityChange() }
        list.isHidden = !hasData || !isRecord
        activity.isHidden = !hasData || showsMap || isRecord || world.projects.isEmpty
        var height = y
        if !activity.isHidden {
            let officeOpen = office != nil
            var selectedID: String?
            if case .actor(let id)? = selection { selectedID = id }
            activity.setFrameOrigin(CGPoint(x: 0, y: y))
            activity.update(activityRows(), title: officeOpen ? "담당자" : "프로젝트", scope: officeOpen ? officeRoot! : "projects",
                            selected: selectedID, maxHeight: 270)
            height = activity.frame.maxY
        } else if !list.isHidden {
            list.frame = CGRect(x: 0, y: y, width: bounds.width, height: 240)
            list.update(office?.list ?? building!.list)
            height = list.frame.maxY
        } else if !scene.isHidden {
            scene.setFrameOrigin(CGPoint(x: 0, y: y))
            renderScene()
            layoutOverlay()
            height = scene.frame.maxY
        }
        if bounds.height != height {
            setFrameSize(CGSize(width: Self.size.width, height: height))
            onHeightChange(height)
        }
    }

    private func activityRows() -> [ActivityRow] {
        if office != nil {
            return people.map { person in
                let activity: ProjectSummary.Activity = switch person.pose {
                case .ask, .error: .attention
                case .work: .working
                case .stopped: .paused
                case .done: .complete
                default: .waiting
                }
                let owned = officeIndex.flatMap { world.projects[$0].activePlan }?.units.first {
                    $0.owner?.terminal == person.id && [.build, .verify, .review].contains($0.phase)
                }
                let detail = person.statusText ?? owned.map { [$0.id, $0.title, $0.phase.label].compactMap { $0 }.joined(separator: " · ") }
                    ?? person.model ?? person.harness.rawValue
                return ActivityRow(id: person.id, title: person.name, detail: detail, state: person.stateText, activity: activity,
                                   face: FloorAgent(coat: person.coat, pose: person.pose))
            }
        }
        let featured = building?.ground.floor.map { world.projects[$0].root }
        return summaries.sorted { $0.priority < $1.priority }.map { summary in
            let sender = summary.root == featured ? summary.requester : nil
            return ActivityRow(id: summary.root, title: summary.name, detail: sender.map { "요청자 " + $0 } ?? summary.detail,
                               state: summary.state, activity: summary.activity, face: summary.face)
        }
    }

    func tick() { if !scene.isHidden { frameNo ^= 1; renderScene() } }

    private func renderScene() {
        let img = office.map { SceneRenderer.render($0.scene, frame: frameNo) } ?? SceneRenderer.render(building!.scene, frame: frameNo)
        scene.base.image = img.base; scene.fx.image = img.fx
        if let o = office {
            let p = world.projects[officeIndex!], plan = p.activePlan
            scene.base.setAccessibilityLabel("\(p.name) 사무실. 담당자 \(o.scene.actors.count)명" + (plan.map { ", 완료 \($0.doneCount)/\($0.units.count)" } ?? "") + ". 같은 정보가 목록 보기에 글자로 있습니다.")
        } else {
            scene.base.setAccessibilityLabel("건물 단면도. 층 \(world.projects.count)개. 같은 정보가 목록 보기에 글자로 있습니다.")
        }
    }

    private func layoutOverlay() {
        let ov = scene.overlay
        let focusedKind = ov.subviews.compactMap { $0 as? HitButton }.first { $0.isFocused }?.kind
        ov.subviews.forEach { $0.removeFromSuperview() }
        ov.night = office?.scene.night ?? building!.scene.night
        ov.labels = office?.scene.labels ?? building!.scene.labels
        for h in office?.scene.hits ?? building!.scene.hits {
            let b = HitButton(h.kind, label: h.label)
            let v = CGRect(x: h.rect.minX * 2, y: h.rect.minY * 2, width: h.rect.width * 2, height: h.rect.height * 2)
            // 클릭 영역을 넓힌다. 선반의 상자는 옆으로 붙어 있어 위아래만 넓힌다. 높이는 화면 24pt(장면 좌표 48) 이상.
            // 선반 두 단은 화면 16pt 간격이라 넓힌 영역이 겹친다. 겹친 곳은 나중에 놓인 상자가 받는다.
            let dx: CGFloat = if case .actor = h.kind { 4 } else { 0 }
            let dy = max(4, (48 - v.height) / 2)
            b.frame = v.insetBy(dx: -dx, dy: -dy); b.visual = CGRect(x: dx, y: dy, width: v.width, height: v.height)
            b.on = h.kind == selection
            b.onPress = { [unowned self] in
                if case .floor(let i) = h.kind { enter(i); return }
                selectTarget(h.kind)
            }
            ov.addSubview(b)
            if h.kind == focusedKind { window?.makeFirstResponder(b) }
        }
        ov.nameTag = nil
        if let o = office, case .actor(let id)? = selection, let a = o.scene.actors.first(where: { $0.id == id }) {
            let p = a.spot.point
            let x = CGFloat(p.x * 2), feet = CGFloat(p.y * 2)
            // 이름표는 발 아래에 둔다. 바닥에 가까운 자리는 아래가 모자라서 몸을 가린다. 그래서 옆에 둔다: 벨 자리는 왼쪽, 소파는 소파의 오른쪽(96).
            let half = SceneOverlay.signWidth(a.name) / 2, h = SceneOverlay.signH
            var tag: (x: CGFloat, y: CGFloat)
            if feet + 2 + h <= 216 - 2 { tag = (x, feet + 2) }
            else if a.spot == .bell { tag = (x - 12 - 8 - half, feet - 16 - h / 2) }
            else { tag = (96 + 4 + half, feet - 16 - h / 2) }
            // 긴 이름도 장면 밖으로 나가지 않게 한다.
            tag.x = max(half + 4, min(480 - half - 4, tag.x))
            ov.nameTag = (a.name, tag.x, tag.y)
        }
        ov.bubble = bubble()
        ov.needsDisplay = true
    }

    // MARK: 말풍선

    /// 상태 문구가 바뀐 직후 3.2초, 가장 최근 것 하나. 자리는 시안의 syncHits를 옮겼다.
    private func bubble() -> SceneOverlay.Bubble? {
        bubbleTimer?.invalidate(); bubbleTimer = nil
        guard let o = office, mode == .office else { return nil }
        noteSaid()
        // 고른 것이 있으면 말풍선을 띄우지 않는다. 글자를 키운 말풍선이 고른 상자나 이름표를 가린다.
        guard selection == nil else { return nil }
        let now = Date()
        let live = o.scene.bubbles.enumerated().compactMap { i, b -> (MonitorScene.Bubble, Date, Int)? in
            guard let s = said[b.actorID], s.text == b.text, now.timeIntervalSince(s.at) < 3.2 else { return nil }
            return (b, s.at, i)
        }
        guard let (sp, at, _) = live.max(by: { ($0.1, $0.2) < ($1.1, $1.2) }) else { return nil }
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, 3.2 - now.timeIntervalSince(at)), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.scene.overlay.bubble = self.bubble(); self.scene.overlay.needsDisplay = true
        }
        let W = 240.0
        // 장면 좌표(480)로 잰다. 글자는 화면 10pt, 말풍선 높이는 화면 14pt.
        let wpx = min(Line(sp.text, SceneOverlay.font, .black).width + 16, 480 * 0.7)
        let w = wpx / 2, h = Double(SceneOverlay.signH) / 2, cx = sp.anchor.x, y0 = max(h + 5, sp.anchor.y)
        func fit(_ x: Double) -> Double { min(W - w / 2 - 4, max(w / 2 + 4, x)) }
        func over(_ v: (Double, Double), _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> Bool {
            x0 < v.0 + w / 2 && x1 > v.0 - w / 2 && y0 < v.1 && y1 > v.1 - h
        }
        let others = o.scene.actors.filter { $0.id != sp.actorID }.map { a -> (SceneActor, SpriteBounds) in
            let p = a.spot.point
            return (a, spriteBounds(x: p.x, y: p.y, coat: a.coat, pose: a.pose))
        }
        func cost(_ v: (Double, Double)) -> Int {
            let box = o.scene.boxes.contains { let p = $0.place.point; return over(v, Double(p.x), Double(p.x + 11), Double(p.y - 1), Double(p.y + 8)) }
            let face = others.contains { over(v, Double($0.1.bx), Double($0.1.bx + 12), Double($0.1.by), Double($0.1.by + 8)) }
            let glyph = others.contains { [.sleep, .stopped, .done].contains($0.0.pose) && over(v, Double($0.1.bx + 2), Double($0.1.bx + 11), Double($0.1.top), Double($0.1.by)) }
            return (box ? 4 : 0) + (face ? 2 : 0) + (glyph ? 1 : 0)
        }
        let xs = [cx, cx - w / 2 + 1, cx + w / 2 - 1].map(fit)
        let cands = xs.map { ($0, y0) } + xs.map { ($0, max(h + 5, y0 - 10)) }
        let best = cands.dropFirst().reduce(cands[0]) { cost($1) < cost($0) ? $1 : $0 }
        let tx = max(8 - wpx / 2, min(wpx / 2 - 8, (cx - best.0) * 2))
        let rect = CGRect(x: best.0 * 2 - wpx / 2, y: best.1 * 2 - SceneOverlay.signH, width: wpx, height: SceneOverlay.signH)
        return .init(text: sp.text, rect: rect, tailX: rect.midX + tx)
    }

    // MARK: 지반

    private static let demoNotice = "예시입니다. 지시는 보내지 않습니다"
    private static let noPhase = "phase.sh를 찾지 못했습니다. MMCODE_MONITOR_PHASE에 경로를 적으세요"

    private func groundSpec() -> GroundSpec {
        if !demo && hcMissing {
            return GroundSpec(turn: false, icon: .building, title: "hc를 찾지 못했습니다", detail: "herdr-core의 hc를 설치하거나 MMCODE_MONITOR_HC에 경로를 적으세요", buttons: [], connection: .offline)
        }
        if !demo && hcDown {
            return GroundSpec(turn: false, icon: .building, title: "hc에서 목록을 읽지 못했습니다", detail: "hc 서버가 켜져 있는지 보세요. 연결되면 다시 읽습니다", buttons: [], connection: .offline)
        }
        if !demo && !loaded {
            return GroundSpec(turn: false, icon: .building, title: "hc에서 터미널 목록을 읽는 중입니다", detail: "잠시 기다리세요", buttons: [], connection: .connecting)
        }
        var g = office?.ground ?? building!.ground
        if let f = form {
            // 메시지는 받는 캐릭터의 얼굴을 보인다.
            var icon = g.icon
            if case .message(let t, _) = f.kind, let a = people.first(where: { $0.id == t }) { icon = .face(a.coat, a.pose) }
            return formSpec(f.root, f.kind, icon: icon, turn: g.turn)
        }
        if let root = confirmStop { return confirmSpec(root) }
        if let o = office, mode == .office, let s = selection, var g = selectionSpec(o, s) {
            if let notice, noticeRoot == officeRoot { g.detail = notice }
            return g
        }
        if office == nil, g.turn, let i = g.floor {
            let local = SceneBuilder.projectGround(world, at: i)
            if !local.buttons.isEmpty { g.buttons = local.buttons }
        }
        var spec = GroundSpec(turn: g.turn, icon: g.icon, title: g.title, pill: g.pill, detail: g.detail, buttons: [])
        if office == nil {
            let working = summaries.reduce(0) { $0 + $1.working }
            if g.turn, let i = g.floor {
                spec.title = "\(world.projects[i].name) · \(summaries[i].state)"
            } else if g.floor == nil && !summaries.isEmpty {
                spec.title = "지금 답할 요청은 없어요"
                spec.detail = working == 0 ? "프로젝트 \(summaries.count)개 · 연결된 에이전트 \(summaries.reduce(0) { $0 + $1.agents })명" : "프로젝트 \(summaries.count)개 · 에이전트 \(working)명 작업 중"
            }
        }
        let root = g.floor.flatMap { world.projects.indices.contains($0) ? world.projects[$0].root : nil }
        let canSend = demo || root.flatMap(phasePath) != nil
        var held: [GroundAction] = []
        for b in g.buttons {
            if case .enterFloor(let i) = b.action {
                let label = "프로젝트 열기"
                spec.buttons.append(.init(label: label, aria: "\(world.projects[i].name) \(label)", primary: b.primary, disabled: b.disabled) { [unowned self] in enter(i) })
            } else if let root, canSend || Self.viaHc(b.action), !isPlaceholder(b.action) {
                var question: ScreenQuestion?
                if case .choose(let t, _) = b.action {
                    question = g.floor.flatMap { world.projects[$0].terminals.first { $0.address == t }?.question }
                    spec.question = question
                }
                spec.buttons.append(.init(label: b.label, aria: aria(b), primary: b.primary, disabled: b.disabled || sending || sent.contains(scoped(root, Self.key(b.action))), command: b.action) { [unowned self, question] in act(b.action, root: root, question: question) })
            } else {
                held.append(b.action)
            }
        }
        if !held.isEmpty {
            let guidance = canSend ? hint(held, floor: g.floor) : Self.noPhase
            if let guidance { spec.detail = office == nil ? g.detail + "\n" + guidance : guidance }
        }
        if let notice, root == noticeRoot { spec.detail = office == nil ? spec.detail + "\n" + notice : notice }
        return spec
    }

    private func phasePath(_ root: String) -> String? {
        if phaseFound == nil { phaseFound = PhaseClient.locate(root: root) }
        return phaseFound
    }

    /// 다음 기록 갱신(Store onChange)에서 부른다.
    func recordsChanged() { sent = [] }

    /// 같은 버튼인지 가리는 값. 답은 결정 ID, 메시지는 받는 터미널.
    static func key(_ a: GroundAction) -> String {
        switch a {
        case .answer(let d, _), .reply(let d): return "d:" + d
        case .message(let t): return "m:" + t
        case .choose(let t, _): return "c:" + t
        case .stopAfter: return "stop-after"
        case .interrupt: return "interrupt"
        case .resume: return "resume"
        case .enterFloor(let i): return "floor:\(i)"
        }
    }

    /// phase.sh 없이 hc로 보내는 동작.
    static func viaHc(_ a: GroundAction) -> Bool {
        switch a { case .message, .choose: return true; default: return false }
    }

    /// 기록에 없는 결정(멈춤만 있는 것)은 ID가 없어 답을 보낼 수 없다.
    private func isPlaceholder(_ a: GroundAction) -> Bool {
        switch a { case .answer(let d, _), .reply(let d): return d.hasPrefix("halt:"); default: return false }
    }

    private func aria(_ b: GroundButton) -> String {
        switch b.action {
        case .answer(_, let t): return "\(t)로 답하기"
        case .interrupt: return "즉시 중단"
        case .choose(_, let n): return "\(n)번 \(b.label) 고르기"
        case .resume: return "계속 진행하라고 지시"
        default: return b.label
        }
    }

    /// 보낼 수 없는 답 버튼 대신 지금 할 수 있는 일을 적는다.
    private func hint(_ held: [GroundAction], floor: Int?) -> String? {
        let p = floor.flatMap { world.projects.indices.contains($0) ? world.projects[$0] : nil }
        for case .answer(let d, _) in held { return answerHint(p, d) }
        for case .reply(let d) in held { return answerHint(p, d) }
        return nil
    }

    private func answerHint(_ p: Project?, _ d: String) -> String {
        let t = p?.plans.lazy.compactMap { $0.units.first { "halt:\($0.id)" == d }?.owner?.terminal }.first ?? p?.agents.first?.address
        return "\(t.map { "터미널 \($0)" } ?? "터미널")에서 답하세요"
    }

    // MARK: 보내기

    /// 버튼 하나의 동작. 입력이 필요하거나 되돌리기 어려운 것은 먼저 지반을 바꾼다.
    private func act(_ a: GroundAction, root: String, question: ScreenQuestion? = nil) {
        switch a {
        case .reply(let d):
            let q = world.projects.first { $0.root == root }?.plans.lazy.compactMap { $0.decisions.first { $0.id == d } }.first?.question ?? d
            form = (root, .reply(decision: d, question: q)); notice = nil; reload()
        case .message(let t):
            let n = world.projects.first { $0.root == root }?.terminals.first { $0.address == t }.map(SceneBuilder.name) ?? t
            form = (root, .message(terminal: t, name: n)); notice = nil; reload()
        case .interrupt: confirmStop = root; notice = nil; reload()
        case .answer(let d, let text): send(root, Self.key(a)) { PhaseClient.answer(phase: $0, root: root, decision: d, text: text) }
        case .stopAfter: send(root, Self.key(a)) { PhaseClient.direct(phase: $0, root: root, .stopAfter) }
        case .resume: send(root, Self.key(a)) { PhaseClient.direct(phase: $0, root: root, .resume) }
        case .choose(let t, let n): choose(root, terminal: t, number: n, question: question)
        case .enterFloor(let i): enter(i)
        }
    }

    /// 보내기 전 공통 검사. 보내면 안 되면 안내를 적고 false.
    private func scoped(_ root: String, _ key: String) -> String { root + "\0" + key }

    private func mayDeliver(_ key: String, root: String) -> Bool {
        guard !sending, !sent.contains(key) else { return false }
        noticeRoot = root
        if demo { form = nil; confirmStop = nil; notice = Self.demoNotice; reload(); return false }
        if noSend { form = nil; confirmStop = nil; notice = "화면 찍기에서는 보내지 않습니다"; reload(); return false }
        return true
    }

    private func terminalName(_ root: String, _ t: String) -> String {
        world.projects.first { $0.root == root }?.terminals.first { $0.address == t }.map(SceneBuilder.name) ?? t
    }

    /// 메시지를 `hc send`로 터미널에 붙여 넣고 Enter를 누른다. `--force`를 쓰지 않으므로 질문 창에는 답하지 않는다.
    /// hc는 사용자의 미완성 입력을 최대 60초 기다린다. 그래서 70초까지 기다린다.
    private func message(_ root: String, terminal t: String, text: String) {
        let n = terminalName(root, t)
        deliver(root, "m:" + t) { HcClient.write("send", address: t, text, timeout: 70).map { ("보내지 못했습니다: \($0)", false) } ?? ("\(n)에게 보냈습니다", true) }
    }

    /// 객관식 선택지를 고른다. 화면을 다시 읽어 같은 질문·같은 선택지일 때만 숫자 키를 누른다.
    private func choose(_ root: String, terminal t: String, number: Int, question: ScreenQuestion?) {
        guard let q = question,
              let o = q.options.first(where: { $0.number == number }) else { return }
        deliver(root, "c:" + t) {
            guard let screen = try? HcClient.read(address: t, lines: 0), QuestionScreen.parse(screen) == q else { return ("질문이 바뀌었습니다. 다시 보세요", false) }
            return HcClient.write("keys", address: t, String(number), timeout: 5).map { ("보내지 못했습니다: \($0)", false) } ?? ("골랐습니다: \(o.label)", true)
        }
    }

    /// hc 쓰기를 백그라운드에서 실행하고 결과 글을 지반에 적는다. 보낸 뒤 5초 또는 다음 갱신까지 같은 버튼을 막는다.
    private func deliver(_ root: String, _ localKey: String, _ op: @escaping () -> (text: String, ok: Bool)) {
        let key = scoped(root, localKey)
        guard mayDeliver(key, root: root) else { return }
        sending = true; notice = "보내는 중입니다"; reload()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let r = op()
            DispatchQueue.main.async { [self] in
                sending = false; form = nil; notice = r.text
                if r.ok {
                    sent.insert(key)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in sent.remove(key); reload() }
                }
                reload()
            }
        }
    }

    /// 큐에서 phase.sh를 부르고 끝나면 지반의 작은 글에 결과를 적는다. 보내는 동안은 다시 보내지 않는다.
    /// 기록 파일이 바뀌면 감시자가 화면을 다시 읽는다.
    private func send(_ root: String, _ localKey: String, _ op: @escaping (String) -> PhaseClient.Outcome) {
        let key = scoped(root, localKey)
        guard mayDeliver(key, root: root) else { return }
        guard let phase = phasePath(root) else { form = nil; confirmStop = nil; notice = Self.noPhase; reload(); return }
        sending = true; notice = "보내는 중입니다"; reload()
        // 패널은 앱이 끝날 때까지 산다. 그래서 self를 강하게 잡는다.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let r = op(phase)
            DispatchQueue.main.async { [self] in
                sending = false; form = nil; confirmStop = nil; notice = Self.resultText(r)
                switch r {
                // 옛 판이거나 고장 난 phase.sh일 수 있다. 경로를 보이고 다음에 다시 찾는다.
                // ponytail: 다음 후보로 넘어가지 않는다. 그런 일이 잦으면 locate가 후보 목록을 돌려주게 바꾼다.
                case .usage, .failed: notice! += " (\(phase))"; phaseFound = nil
                case .ok, .noReply:
                    // 이미 적혔을 수 있으니 기록을 다시 읽을 때까지 같은 버튼을 막는다.
                    sent.insert(key)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in sent.remove(key); reload() }
                case .refused: break
                }
                reload()
            }
        }
    }

    static func resultText(_ r: PhaseClient.Outcome) -> String {
        switch r {
        case .ok(let line):
            let id = line.hasPrefix("OK: ") ? line.dropFirst(4).split(separator: " ").first.map(String.init) : nil
            if let id, id.hasPrefix("D") { return "\(id)에 답했습니다" }
            if let id, id.hasPrefix("I") { return "\(id) 지시를 보냈습니다" }
            return "보냈습니다"
        case .refused(let m), .usage(let m), .failed(let m): return "보내지 못했습니다: \(m)"
        case .noReply: return "응답이 없습니다. 적혔는지 목록에서 보세요"
        }
    }

    private func formSpec(_ root: String, _ kind: Form, icon: GroundIcon, turn: Bool) -> GroundSpec {
        let close = GroundSpec.Button(label: "", aria: "입력 닫기", close: true) { [unowned self] in form = nil; reload() }
        let label: String, placeholder: String, id: String, submit: (String) -> Void
        switch kind {
        case .reply(let d, let q):
            (label, placeholder, id) = ("답: \(q)", "답을 적으세요", "reply:\(root):\(d)")
            submit = { [unowned self] t in send(root, "d:" + d) { PhaseClient.answer(phase: $0, root: root, decision: d, text: t) } }
        case .message(let t, let n):
            (label, placeholder, id) = ("\(n)에게 보낼 메시지", "예: 시험부터 다시 실행해 줘", "message:\(root):\(t)")
            submit = { [unowned self] text in message(root, terminal: t, text: text) }
        }
        // 빈 글은 보내지 않는다.
        let go: (String) -> Void = { t in let v = t.trimmingCharacters(in: .whitespacesAndNewlines); if !v.isEmpty { submit(v) } }
        let sendBtn = GroundSpec.Button(label: "보내기", aria: "보내기", primary: true, disabled: sending) { [unowned self] in go(ground.input.field.stringValue) }
        let context = office == nil ? world.projects.first(where: { $0.root == root }).map { $0.name + " · " } ?? "" : ""
        let field = GroundSpec.Field(id: id, label: context + label, placeholder: placeholder, submit: go, cancel: { [unowned self] in form = nil; reload() })
        return GroundSpec(turn: turn, icon: icon, title: label, detail: notice ?? "", buttons: [sendBtn, close], field: field)
    }

    private func confirmSpec(_ root: String) -> GroundSpec {
        GroundSpec(turn: false, icon: .stop, title: (world.projects.first { $0.root == root }?.name ?? "프로젝트") + " 작업을 중단할까요?", detail: notice ?? "즉시 중단해도 미완료 변경은 지우지 않습니다", buttons: [
            .init(label: "멈춘다", aria: "지금 모두 멈춘다", primary: true, disabled: sending || sent.contains(scoped(root, "interrupt"))) { [unowned self] in send(root, "interrupt") { PhaseClient.direct(phase: $0, root: root, .interrupt) } },
            .init(label: "취소", aria: "중단 취소", disabled: sending, focus: true) { [unowned self] in confirmStop = nil; reload() },
        ])
    }

    private func selectionSpec(_ o: OfficeView, _ s: HitTarget.Kind) -> GroundSpec? {
        let close = GroundSpec.Button(label: "", aria: "선택 풀기", close: true) { [unowned self] in selection = nil; notice = nil; reload() }
        switch s {
        case .actor(let id):
            guard let a = people.first(where: { $0.id == id }) else { return nil }
            let pill = [a.harness.rawValue, a.model, a.effort.map { "effort " + $0 }].compactMap { $0 }.joined(separator: ", ")
            let detail = a.stateText + (a.statusText.map { ". " + $0 } ?? "")
            let root = world.projects[officeIndex!].root
            // 객관식 질문이 떠 있으면 질문과 선택지를 보인다. 메시지(hc send)는 질문 창에 들어가지 않으므로 두지 않는다.
            if a.status == .blocked, let q = world.projects[officeIndex!].terminals.first(where: { $0.address == id })?.question {
                let choices = SceneBuilder.choiceButtons(terminal: id, q).map { b in
                    GroundSpec.Button(label: b.label, aria: aria(b), disabled: sending || sent.contains(scoped(root, Self.key(b.action))), command: b.action) { [unowned self] in act(b.action, root: root, question: q) }
                }
                return GroundSpec(turn: true, icon: .face(a.coat, a.pose), title: q.text, detail: "\(a.name): 입력 대기", buttons: choices + [close], question: q)
            }
            let msg = GroundSpec.Button(label: "메시지", aria: "\(a.name)에게 메시지", primary: true, disabled: sending || sent.contains(scoped(root, "m:" + a.id))) { [unowned self] in
                form = (root, .message(terminal: a.id, name: a.name)); notice = nil; reload()
            }
            return GroundSpec(turn: false, icon: .face(a.coat, a.pose), title: a.name, pill: pill, detail: detail, buttons: [msg, close])
        case .box(let id):
            guard let b = o.scene.boxes.first(where: { $0.id == id }), let i = officeIndex else { return nil }
            let u = world.projects[i].activePlan?.units.first { $0.id == id }
            let ev = u?.latestEvidence.map { "\($0.kind.label) \($0.pass ? "통과" : "실패")\($0.reason.map { " " + $0 } ?? "")" } ?? "아직 없음"
            return GroundSpec(turn: false, icon: .box(number: b.number, done: b.phase == .done), title: b.id + (b.title.map { " " + $0 } ?? ""),
                              pill: "\(b.phase.label) 단계", detail: (b.blocked ? "단위 막힘. " : "") + "최근 증거: " + ev, buttons: [close])
        case .floor: return nil
        }
    }
}

/// 장면의 클릭 영역. 종류를 기억해 다시 그린 뒤에도 초점을 이어 준다.
final class HitButton: PanelButton {
    let kind: HitTarget.Kind
    init(_ kind: HitTarget.Kind, label: String) { self.kind = kind; super.init(.hit, "", label: label) }
    required init?(coder: NSCoder) { nil }
}
