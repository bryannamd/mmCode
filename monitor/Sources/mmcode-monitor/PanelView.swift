import AppKit
import MonitorCore
import MonitorScene

/// 480×300 패널. 화면 상태(보기, 선택, 보이는 층)를 들고 SceneBuilder의 값을 세 층에 나눠 준다.
/// 답과 지시는 PhaseClient(phase.sh answer·direct)로만 보낸다. 예시 자료면 보내지 않는다.
final class PanelView: NSView {
    enum Mode { case office, building, list }
    /// 지반의 입력칸. 다르게 답하기와 메시지.
    enum Form: Equatable { case reply(decision: String, question: String), message(terminal: String, name: String) }

    // 지붕은 28px만 칠한다. 아래 12px은 투명하고 버튼의 클릭 영역(40px)만 장면 위로 내려온다.
    let roof = RoofView(frame: CGRect(x: 0, y: 0, width: 480, height: RoofView.hitHeight))
    let scene = SceneView(frame: CGRect(x: 0, y: 28, width: 480, height: 216))
    let list = ListPane(frame: CGRect(x: 0, y: 28, width: 480, height: 216))
    let ground = GroundView(frame: CGRect(x: 0, y: 244, width: 480, height: 56))

    var world = World()
    var demo = false, hcMissing = false, hcDown = false, loaded = false
    var mode = Mode.building, back = Mode.building
    var officeRoot: String?
    var firstFloor = 0
    var selection: HitTarget.Kind?
    var notice: String?
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
        [scene, list, roof, ground].forEach(addSubview)
        list.isHidden = true
        roof.building.onPress = { [unowned self] in go(mode == .building ? .office : .building) }
        roof.list.onPress = { [unowned self] in go(mode == .list ? back : .list) }
        roof.alert.onPress = { [unowned self] in go(.building) }
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

    func go(_ m: Mode) {
        if m == .office && officeIndex == nil { return }
        if m != .list { back = m }
        mode = m; selection = nil; notice = nil; form = nil; confirmStop = nil
        reload()
    }

    func enter(_ i: Int) {
        guard world.projects.indices.contains(i) else { return }
        officeRoot = world.projects[i].root
        go(.office)
    }

    func scrollFloors(_ d: Int) {
        guard mode == .building else { return }
        let n = max(0, world.projects.count - BuildingLayout.visibleFloors), f = max(0, min(n, firstFloor + d))
        if f != firstFloor { firstFloor = f; reload() }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: escape()
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
        } else {
            if mode == .office { mode = .building }
            back = .building
            office = nil
            let b = SceneBuilder.building(world, firstFloor: firstFloor, night: n)
            building = b; firstFloor = b.scene.firstFloor
        }
        // 사무실로 보는 프로젝트의 기록 파일만 지켜본다.
        let f = office == nil ? nil : officeRoot
        if f != focused { focused = f; onFocus(f) }
        if let o = office, let s = selection {
            let ok: Bool = switch s {
            case .actor(let id): o.scene.actors.contains { $0.id == id }
            case .box(let id): o.scene.boxes.contains { $0.id == id }
            case .floor: false
            }
            if !ok { selection = nil }
        } else { selection = nil }

        roof.update(office?.roof ?? building!.roof, buildingOn: mode == .building, listOn: mode == .list)
        ground.update(groundSpec())
        scene.isHidden = mode == .list; list.isHidden = mode != .list
        if mode == .list { list.update(office?.list ?? building!.list) } else { renderScene(); layoutOverlay() }
    }

    /// 프레임만 바꾼다. 패널이 보일 때만 불린다.
    func tick() { frameNo ^= 1; if mode != .list { renderScene() } }

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
            // 클릭 영역을 넓힌다. 선반의 상자는 옆으로 붙어 있어 위아래만, 층은 위아래 2px만.
            let (dx, dy): (CGFloat, CGFloat) = switch h.kind { case .actor: (4, 4); case .box: (0, 4); case .floor: (0, 2) }
            b.frame = v.insetBy(dx: -dx, dy: -dy); b.visual = CGRect(x: dx, y: dy, width: v.width, height: v.height)
            b.on = h.kind == selection
            b.onPress = { [unowned self] in
                if case .floor(let i) = h.kind { enter(i); return }
                selection = selection == h.kind ? nil : h.kind; notice = nil; form = nil; confirmStop = nil; reload()
            }
            ov.addSubview(b)
            if h.kind == focusedKind { window?.makeFirstResponder(b) }
        }
        ov.nameTag = nil
        if let o = office, case .actor(let id)? = selection, let a = o.scene.actors.first(where: { $0.id == id }) {
            let p = a.spot.point
            let x = CGFloat(p.x * 2), feet = CGFloat(p.y * 2)
            // 이름표는 발 아래에 둔다. 바닥에 가까운 자리는 아래가 모자라서 몸을 가린다. 그래서 옆에 둔다: 벨 자리는 왼쪽, 소파는 소파의 오른쪽(96px).
            let half = (Line(a.name, Theme.jua(12), Theme.ink).width + 16) / 2
            var tag: (x: CGFloat, y: CGFloat)
            if feet + 4 + 20 <= 216 - 2 { tag = (x, feet + 4) }
            else if a.spot == .bell { tag = (x - 12 - 8 - half, feet - 16 - 10) }
            else { tag = (96 + 4 + half, feet - 16 - 10) }
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
        let wpx = min(Line(sp.text, Theme.jua(12), .black).width + 18, 480 * 0.62)
        let w = wpx / 2, h = 10.0, cx = sp.anchor.x, y0 = max(h + 5, sp.anchor.y)
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
        let rect = CGRect(x: best.0 * 2 - wpx / 2, y: best.1 * 2 - 20, width: wpx, height: 20)
        return .init(text: sp.text, rect: rect, tailX: rect.midX + tx)
    }

    // MARK: 지반

    private static let demoNotice = "예시입니다. 지시는 보내지 않습니다"
    private static let noPhase = "phase.sh를 찾지 못했습니다. MMCODE_MONITOR_PHASE에 경로를 적으세요"

    private func groundSpec() -> GroundSpec {
        if !demo && hcMissing {
            return GroundSpec(turn: false, icon: .building, title: "hc를 찾지 못했습니다", detail: "herdr-core의 hc를 설치하거나 MMCODE_MONITOR_HC에 경로를 적으세요", buttons: [])
        }
        if !demo && hcDown {
            return GroundSpec(turn: false, icon: .building, title: "hc에서 목록을 읽지 못했습니다", detail: "hc 서버가 켜져 있는지 보세요. 연결되면 다시 읽습니다", buttons: [])
        }
        if !demo && !loaded {
            return GroundSpec(turn: false, icon: .building, title: "hc에서 터미널 목록을 읽는 중입니다", detail: "잠시 기다리세요", buttons: [])
        }
        let g = office?.ground ?? building!.ground
        if let f = form {
            // 메시지는 받는 캐릭터의 얼굴을 보인다.
            var icon = g.icon
            if case .message(let t, _) = f.kind, let a = office?.scene.actors.first(where: { $0.id == t }) { icon = .face(a.coat, a.pose) }
            return formSpec(f.root, f.kind, icon: icon, turn: g.turn)
        }
        if let root = confirmStop { return confirmSpec(root) }
        if let o = office, mode == .office, let s = selection, var g = selectionSpec(o, s) {
            if let notice { g.detail = notice }
            return g
        }
        var spec = GroundSpec(turn: g.turn, icon: g.icon, title: g.title, pill: g.pill, detail: g.detail, buttons: [])
        let root = g.floor.flatMap { world.projects.indices.contains($0) ? world.projects[$0].root : nil }
        let canSend = demo || root.flatMap(phasePath) != nil
        var held: [GroundAction] = []
        for b in g.buttons {
            if case .enterFloor(let i) = b.action {
                spec.buttons.append(.init(label: b.label, aria: "\(b.label): \(world.projects.indices.contains(i) ? world.projects[i].name : "")", primary: b.primary, disabled: b.disabled) { [unowned self] in enter(i) })
            } else if let root, canSend, !isPlaceholder(b.action) {
                spec.buttons.append(.init(label: b.label, aria: aria(b), primary: b.primary, disabled: b.disabled || sending || sent.contains(Self.key(b.action))) { [unowned self] in act(b.action, root: root) })
            } else {
                held.append(b.action)
            }
        }
        if !held.isEmpty { spec.detail = canSend ? hint(held, floor: g.floor) ?? spec.detail : Self.noPhase }
        if let notice { spec.detail = notice }
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
        case .stopAfter: return "stop-after"
        case .interrupt: return "interrupt"
        case .resume: return "resume"
        case .enterFloor(let i): return "floor:\(i)"
        }
    }

    /// 기록에 없는 결정(멈춤만 있는 것)은 ID가 없어 답을 보낼 수 없다.
    private func isPlaceholder(_ a: GroundAction) -> Bool {
        switch a { case .answer(let d, _), .reply(let d): return d.hasPrefix("halt:"); default: return false }
    }

    private func aria(_ b: GroundButton) -> String {
        switch b.action {
        case .answer(_, let t): return "\(t)로 답하기"
        case .interrupt: return "즉시 중단"
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
    private func act(_ a: GroundAction, root: String) {
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
        case .enterFloor(let i): enter(i)
        }
    }

    /// 큐에서 phase.sh를 부르고 끝나면 지반의 작은 글에 결과를 적는다. 보내는 동안은 다시 보내지 않는다.
    /// 기록 파일이 바뀌면 감시자가 화면을 다시 읽는다.
    private func send(_ root: String, _ key: String, _ op: @escaping (String) -> PhaseClient.Outcome) {
        guard !sending, !sent.contains(key) else { return }
        if demo { form = nil; confirmStop = nil; notice = Self.demoNotice; reload(); return }
        if noSend { form = nil; confirmStop = nil; notice = "화면 찍기에서는 보내지 않습니다"; reload(); return }
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
            submit = { [unowned self] text in send(root, "m:" + t) { PhaseClient.direct(phase: $0, root: root, .message, text: text, terminal: t) } }
        }
        // 빈 글은 보내지 않는다.
        let go: (String) -> Void = { t in let v = t.trimmingCharacters(in: .whitespacesAndNewlines); if !v.isEmpty { submit(v) } }
        let sendBtn = GroundSpec.Button(label: "보내기", aria: "보내기", primary: true, disabled: sending) { [unowned self] in go(ground.input.field.stringValue) }
        let field = GroundSpec.Field(id: id, label: label, placeholder: placeholder, submit: go, cancel: { [unowned self] in form = nil; reload() })
        return GroundSpec(turn: turn, icon: icon, title: label, detail: notice ?? "", buttons: [sendBtn, close], field: field)
    }

    private func confirmSpec(_ root: String) -> GroundSpec {
        GroundSpec(turn: false, icon: .stop, title: "지금 모두 멈출까요?", detail: notice ?? "즉시 중단해도 미완료 변경은 지우지 않습니다", buttons: [
            .init(label: "멈춘다", aria: "지금 모두 멈춘다", primary: true, disabled: sending || sent.contains("interrupt")) { [unowned self] in send(root, "interrupt") { PhaseClient.direct(phase: $0, root: root, .interrupt) } },
            .init(label: "취소", aria: "중단 취소", disabled: sending, focus: true) { [unowned self] in confirmStop = nil; reload() },
        ])
    }

    private func selectionSpec(_ o: OfficeView, _ s: HitTarget.Kind) -> GroundSpec? {
        let close = GroundSpec.Button(label: "", aria: "선택 풀기", close: true) { [unowned self] in selection = nil; notice = nil; reload() }
        switch s {
        case .actor(let id):
            guard let a = o.scene.actors.first(where: { $0.id == id }) else { return nil }
            let pill = [a.harness.rawValue, a.model, a.effort.map { "effort " + $0 }].compactMap { $0 }.joined(separator: ", ")
            var detail = a.stateText + (a.statusText.map { ". " + $0 } ?? "")
            var btns = [close]
            let root = world.projects[officeIndex!].root
            if demo || phasePath(root) != nil {
                btns.insert(.init(label: "메시지", aria: "\(a.name)에게 메시지", primary: true, disabled: sending || sent.contains("m:" + a.id)) { [unowned self] in
                    form = (root, .message(terminal: a.id, name: a.name)); notice = nil; reload()
                }, at: 0)
            } else { detail += ". " + Self.noPhase }
            return GroundSpec(turn: false, icon: .face(a.coat, a.pose), title: a.name, pill: pill, detail: detail, buttons: btns)
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
