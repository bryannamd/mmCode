import AppKit
import MonitorCore
import MonitorScene

/// 480×300 패널. 화면 상태(보기, 선택, 보이는 층)를 들고 SceneBuilder의 값을 세 층에 나눠 준다.
/// 이번 판은 읽기 전용이다. 지시를 보내는 코드는 없다.
final class PanelView: NSView {
    enum Mode { case office, building, list }

    let roof = RoofView(frame: CGRect(x: 0, y: 0, width: 480, height: 28))
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        [scene, list, roof, ground].forEach(addSubview)
        list.isHidden = true
        roof.building.onPress = { [unowned self] in go(mode == .building ? .office : .building) }
        roof.list.onPress = { [unowned self] in go(mode == .list ? back : .list) }
        roof.alert.onPress = { [unowned self] in go(.building) }
        scene.overlay.onEmptyClick = { [unowned self] in if selection != nil || notice != nil { selection = nil; notice = nil; reload() } }
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
        mode = m; selection = nil; notice = nil
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

    /// Esc: 선택이나 안내를 먼저 풀고, 없으면 패널을 닫는다.
    func escape() {
        if selection != nil || notice != nil { selection = nil; notice = nil; reload(); window?.makeFirstResponder(self) } else { onClose() }
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
                selection = selection == h.kind ? nil : h.kind; notice = nil; reload()
            }
            ov.addSubview(b)
            if h.kind == focusedKind { window?.makeFirstResponder(b) }
        }
        ov.nameTag = nil
        if let o = office, case .actor(let id)? = selection, let a = o.scene.actors.first(where: { $0.id == id }) {
            let p = a.spot.point
            ov.nameTag = (a.name, CGFloat(p.x * 2), min(CGFloat(p.y * 2 + 4), 216 - 22))
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
        if let o = office, mode == .office, let s = selection, var g = selectionSpec(o, s) {
            if let notice { g.detail = notice }
            return g
        }
        let g = office?.ground ?? building!.ground
        var spec = GroundSpec(turn: g.turn, icon: g.icon, title: g.title, pill: g.pill, detail: g.detail, buttons: [])
        var writes: [GroundAction] = []
        for b in g.buttons {
            if case .enterFloor(let i) = b.action {
                spec.buttons.append(.init(label: b.label, aria: "\(b.label): \(world.projects.indices.contains(i) ? world.projects[i].name : "")", primary: b.primary, disabled: b.disabled) { [unowned self] in enter(i) })
            } else if demo {
                spec.buttons.append(.init(label: b.label, aria: b.action == .interrupt ? "즉시 중단" : b.label, primary: b.primary, disabled: b.disabled) { [unowned self] in
                    notice = Self.demoNotice; reload()
                })
            } else {
                writes.append(b.action)
            }
        }
        if let h = hint(writes, floor: g.floor) { spec.detail += ". " + h }
        if let notice { spec.detail = notice }
        return spec
    }

    /// 보낼 수 없는 버튼 대신 지금 할 수 있는 일을 적는다.
    private func hint(_ writes: [GroundAction], floor: Int?) -> String? {
        let p = floor.flatMap { world.projects.indices.contains($0) ? world.projects[$0] : nil }
        let first = p?.agents.first?.address
        func at(_ a: String?) -> String { a.map { "터미널 \($0)" } ?? "터미널" }
        for w in writes {
            switch w {
            case .answer(let d, _), .reply(let d):
                let plan = p?.activePlan
                let asker = plan?.decisions.first { $0.id == d }?.asker?.terminal
                    ?? plan?.units.first { "halt:\($0.id)" == d }?.owner?.terminal
                return "\(at(asker ?? first))에서 답하세요"
            case .message(let t): return "\(at(t))에서 메시지를 보내세요"
            case .resume: return "계속하려면 \(at(first))에서 지시하세요"
            default: continue
            }
        }
        return nil
    }

    private func selectionSpec(_ o: OfficeView, _ s: HitTarget.Kind) -> GroundSpec? {
        let close = GroundSpec.Button(label: "", aria: "선택 풀기", close: true) { [unowned self] in selection = nil; notice = nil; reload() }
        switch s {
        case .actor(let id):
            guard let a = o.scene.actors.first(where: { $0.id == id }) else { return nil }
            let pill = [a.harness.rawValue, a.model, a.effort.map { "effort " + $0 }].compactMap { $0 }.joined(separator: ", ")
            var detail = a.stateText + (a.statusText.map { ". " + $0 } ?? "")
            var btns = [close]
            if demo { btns.insert(.init(label: "메시지", aria: "\(a.name)에게 메시지", primary: true) { [unowned self] in notice = Self.demoNotice; reload() }, at: 0) }
            else { detail += ". 메시지는 터미널 \(a.id)에서" }
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
