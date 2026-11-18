import AppKit
import MonitorCore
import MonitorScene

// 패널의 세 층: 지붕(22), 장면(108) 또는 목록, 지반(50). 모두 화면 pt다. 장면만 480×216 그림을 0.5배로 줄인다.
// 글자는 화면에서 10pt 이상이다(지반 제목 13pt).

// MARK: 지붕

/// 건물 버튼, 프로젝트 이름, 완료 수, 목록 버튼, "예시" 표지. 다른 층 알림은 건물 버튼을 분홍으로 바꿔 알린다(폭 240pt에는 알림 문구가 들어가지 않는다).
final class RoofView: FocusHost {
    static let height: CGFloat = 22, hitHeight: CGFloat = 26
    let building = PanelButton(.nav, "건물", label: "건물 보기")
    let list = PanelButton(.nav, "목록", label: "목록 보기")
    private var model: RoofModel?
    private var nameX: CGFloat = 0, nameMax: CGFloat = 0, countX: CGFloat = 0, demoRect = CGRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        [building, list].forEach(addSubview)
    }
    required init?(coder: NSCoder) { nil }

    func update(_ m: RoofModel, buildingOn: Bool, listOn: Bool) {
        model = m
        building.on = buildingOn; list.on = listOn
        building.alarm = m.alert != nil
        building.setAccessibilityLabel((buildingOn ? "건물 보기 닫기" : "건물 보기") + (m.alert.map { ". 다른 층 알림: \($0.long)" } ?? ""))
        list.setAccessibilityLabel(listOn ? "목록 보기 닫기" : "목록 보기")
        var right = bounds.width - 4
        if m.isDemo {
            let w = Line("예시", Theme.body(10), .black).width + 8
            demoRect = CGRect(x: right - w, y: 4, width: w, height: 14); right -= w + 4
        }
        place(list, right: right); right = list.frame.minX + 2 - 6
        building.frame = CGRect(x: 4 - 2, y: 0, width: building.fitSize.width + 4, height: Self.hitHeight)
        building.visual = CGRect(x: 2, y: 2, width: building.fitSize.width, height: building.fitSize.height)
        nameX = building.frame.maxX - 2 + 6
        let countW = m.count.map { Line($0, Theme.body(10), .black).width + 6 } ?? 0
        let nameW = Line(m.title, Theme.jua(13), .black).width
        nameMax = max(30, right - nameX - countW)
        countX = nameX + min(nameW, nameMax) + 6
        needsDisplay = true
    }

    private func place(_ b: PanelButton, right: CGFloat) {
        let s = b.fitSize
        // 클릭 영역은 높이 26pt이고 옆으로 2pt 넓힌다.
        b.frame = CGRect(x: right - s.width - 2, y: 0, width: s.width + 4, height: Self.hitHeight)
        b.visual = CGRect(x: 2, y: (Self.height - s.height) / 2, width: s.width, height: s.height)
        b.needsDisplay = true
    }

    /// 지붕 아래로 내려온 띠에서는 버튼만 클릭을 받는다. 나머지는 장면으로 넘긴다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        return v === self && convert(point, from: superview).y >= Self.height ? nil : v
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.ink.setFill(); CGRect(x: 0, y: 0, width: bounds.width, height: Self.height).fill()
        drawFocus()
        guard let m = model else { return }
        Line(m.title, Theme.jua(13), Theme.paper).draw(x: nameX, cy: 11, maxWidth: nameMax)
        if let c = m.count { Line(c, Theme.body(10), Theme.onInkSub).draw(x: countX, cy: 11) }
        if m.isDemo {
            fillRound(demoRect, 3, nil, stroke: Theme.ink3, width: 1)
            Line("예시", Theme.body(10), Theme.onInkSub).draw(x: demoRect.minX + 4, cy: demoRect.midY)
        }
    }
}

// MARK: 지반

struct GroundSpec {
    /// `focus`: 지반에 초점이 있을 때 먼저 받을 버튼(예: 중단 확인의 "취소").
    struct Button { var label: String; var aria: String; var primary = false; var disabled = false; var close = false; var focus = false; var press: () -> Void }
    /// 한 줄 입력칸. 제목·설명 대신 이름표와 입력칸을 그린다. `id`가 바뀌면 글을 비우고 초점을 준다.
    struct Field { var id: String; var label: String; var placeholder: String; var submit: (String) -> Void; var cancel: () -> Void }
    var turn: Bool
    var icon: GroundIcon
    var title: String
    var pill: String?
    var detail: String
    var buttons: [Button]
    var field: Field?
}

final class GroundView: FocusHost {
    private var spec: GroundSpec?
    private(set) var buttons: [PanelButton] = []
    private var textMax: CGFloat = 0
    let input = InputBox()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        input.isHidden = true
        addSubview(input)
    }
    required init?(coder: NSCoder) { nil }

    /// 두 줄: 위는 제목(Jua 13), 아래는 작은 글(10)과 오른쪽 버튼(높이 24). 글은 x 40부터, 옆 여백 6.
    static let textX: CGFloat = 40, row1: CGFloat = 12, row2Top: CGFloat = 23, row2: CGFloat = 35

    func update(_ g: GroundSpec) {
        let hadFocus = buttons.contains { $0.isFocused } || input.editing
        spec = g
        focusColor = g.turn ? Theme.ink : Theme.paper
        buttons.forEach { $0.removeFromSuperview() }
        buttons = g.buttons.map { s in
            let b = PanelButton(s.close ? .close : s.primary ? .primary : .outline, s.label, label: s.aria, onPress: s.press)
            b.turn = g.turn; b.disabled = s.disabled; b.focus = s.focus
            return b
        }
        // 버튼은 아래 줄 오른쪽 끝(6pt 여백)부터 6pt 간격. 클릭 영역은 위아래 2pt, 옆 2pt 넓혀 높이 28pt다.
        var right = bounds.width - 6
        for b in buttons.reversed() {
            let s = b.fitSize
            b.frame = CGRect(x: right - s.width - 2, y: Self.row2Top - 2, width: s.width + 4, height: s.height + 4)
            b.visual = CGRect(x: 2, y: 2, width: s.width, height: s.height)
            right -= s.width + 6
            addSubview(b)
        }
        textMax = right - Self.textX
        setAccessibilityLabel(g.field?.label ?? "\(g.title). \(g.pill.map { $0 + ". " } ?? "")\(g.detail)")
        // 입력칸: 위 줄에 이름표, 아래 줄에 버튼 왼쪽까지 24pt 칸.
        if let f = g.field {
            input.frame = CGRect(x: Self.textX, y: Self.row2Top, width: max(40, textMax), height: 24)
            input.isHidden = false
            input.show(f)
        } else {
            input.hide()
        }
        if input.fresh { input.fresh = false; window?.makeFirstResponder(input.field) }
        else if hadFocus, !input.editing, let f = buttons.first(where: { $0.focus && !$0.disabled }) ?? buttons.first(where: { !$0.disabled }) { window?.makeFirstResponder(f) }
        needsDisplay = true
    }

    /// 화면 찍기용. 이름이 같은 첫 버튼을 누른다.
    func press(_ label: String) { buttons.first { $0.title == label && !$0.disabled }?.onPress() }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = spec else { return }
        let fg = g.turn ? Theme.ink : Theme.paper, sub = g.turn ? Theme.ink : Theme.onInkSub
        (g.turn ? Theme.pink : Theme.ink).setFill(); bounds.fill()
        Theme.ink.setFill(); CGRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
        drawFocus()
        // 얼굴 칸: 28pt 원, 종이색. 안의 16칸 그림을 24pt(레티나에서 칸당 3px)로.
        let c = CGRect(x: 6, y: (bounds.height + 2 - 28) / 2, width: 28, height: 28)
        NSGraphicsContext.saveGraphicsState()
        let circle = NSBezierPath(ovalIn: c); Theme.paper.setFill(); circle.fill(); circle.addClip()
        drawPixels(SceneRenderer.icon(g.icon), in: CGRect(x: c.minX + 2, y: c.minY + 2, width: 24, height: 24))
        NSGraphicsContext.restoreGraphicsState()
        let ring = NSBezierPath(ovalIn: c.insetBy(dx: 1, dy: 1)); ring.lineWidth = 2; (g.turn ? Theme.ink : Theme.paper).setStroke(); ring.stroke()
        let x = Self.textX, full = bounds.width - 6 - x
        let title = Line(g.field?.label ?? g.title, Theme.jua(13), fg)
        if g.field != nil { title.draw(x: x, cy: Self.row1, maxWidth: full); return }
        var titleMax = full
        if let p = g.pill { titleMax = max(60, full - Line(p, Theme.body(10, .semibold), .black).width - 16) }
        title.draw(x: x, cy: Self.row1, maxWidth: titleMax)
        if let p = g.pill {
            let pl = Line(p, Theme.body(10, .semibold), fg)
            let px = x + min(title.width, titleMax) + 4, w = min(pl.width + 12, x + full - px)
            let r = CGRect(x: px, y: Self.row1 - 7, width: w, height: 14)
            fillRound(r, 7, nil, stroke: fg, width: 1.5)
            pl.draw(x: r.minX + 6, cy: r.midY, maxWidth: w - 12)
        }
        // 버튼이 줄을 거의 다 쓰면 작은 글은 뺀다. 같은 글은 화면 낭독기 이름에 있다.
        if textMax >= 30 { Line(g.detail, Theme.body(10, .semibold), sub).draw(x: x, cy: Self.row2, maxWidth: textMax) }
    }
}

/// 지반의 한 줄 입력칸. 종이색 칸(모서리 7px) 안에 테두리 없는 NSTextField를 세로 가운데에 둔다.
/// 리턴은 보내기, Esc는 닫기다. 글은 같은 입력칸(`id`)인 동안 남는다(자료가 바뀌어 다시 그려도 지워지지 않는다).
final class InputBox: NSView, NSTextFieldDelegate {
    let field = Field()
    private var spec: GroundSpec.Field?
    private(set) var id: String?
    /// 새로 열렸다. GroundView가 초점을 준다.
    var fresh = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 12); field.textColor = Theme.ink
        field.cell?.usesSingleLineMode = true; field.cell?.isScrollable = true; field.cell?.wraps = false
        field.delegate = self
        field.onFocus = { [weak self] in self?.needsDisplay = true }
        addSubview(field)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    var editing: Bool { field.currentEditor() != nil }

    func show(_ f: GroundSpec.Field) {
        spec = f
        if id != f.id {
            id = f.id; fresh = true
            field.stringValue = ""
            field.placeholderAttributedString = NSAttributedString(string: f.placeholder, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.paperSub])
            field.setAccessibilityLabel(f.label)
        }
        let h = ceil(field.intrinsicContentSize.height)
        field.frame = CGRect(x: 8, y: (bounds.height - h) / 2, width: bounds.width - 16, height: h)
        needsDisplay = true
    }

    func hide() {
        guard id != nil else { return }
        let had = editing
        id = nil; spec = nil; fresh = false; field.stringValue = ""
        if had { window?.makeFirstResponder(nil) }  // 지반이 이어서 첫 버튼에 초점을 준다
        isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        fillRound(bounds, 7, Theme.paper)
        // 초점: 안쪽 2px ink-3 선(시안 outline-offset -2px).
        if editing { fillRound(bounds, 7, nil, stroke: Theme.ink3) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { spec?.submit(field.stringValue); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { spec?.cancel(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }

    final class Field: NSTextField {
        var onFocus: () -> Void = {}
        override func becomeFirstResponder() -> Bool { defer { onFocus() }; return super.becomeFirstResponder() }
    }
}

// MARK: 장면

/// CGImage를 CALayer에 넣고 보간 없이 확대한다. 화면 밖 그리기(--snapshot)에서는 draw로 같은 그림을 그린다.
final class PixelView: NSView {
    var image: CGImage? { didSet { layer?.contents = image } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = image }
    override func draw(_ dirtyRect: NSRect) { if let image { drawPixels(image, in: bounds) } }
}

/// 장면 위의 글자 층: 벽 이름표, 층 이름, 선택한 캐릭터의 이름표, 말풍선, 클릭 영역.
/// 장면은 480×216 좌표를 0.5배로 보인다. 그래서 글자 크기와 이름표 높이는 화면 값의 2배로 적는다(Jua 20 = 화면 10pt).
final class SceneOverlay: FocusHost {
    static let font = Theme.jua(20), signH: CGFloat = 28
    struct Bubble { var text: String; var rect: CGRect; var tailX: CGFloat }
    var labels: [WallLabel] = []
    var night = false
    var bubble: Bubble?
    var nameTag: (text: String, x: CGFloat, y: CGFloat)?
    var onEmptyClick: () -> Void = {}

    override func mouseDown(with event: NSEvent) { onEmptyClick() }

    override func draw(_ dirtyRect: NSRect) {
        drawFocus()
        for l in labels {
            switch l.style {
            case .stage: sign(l.text, cx: l.rect.minX * 2, top: l.rect.minY * 2 + 0.06, fill: night ? Theme.cardNight : Theme.paper)
            case .floorName:
                let r = CGRect(x: l.rect.minX * 2, y: l.rect.minY * 2, width: l.rect.width * 2, height: l.rect.height * 2)
                Line(l.text, Self.font, Theme.ink).draw(x: r.minX + 6, cy: r.midY + 0.5, maxWidth: r.width - 8)
            }
        }
        if let t = nameTag { sign(t.text, cx: t.x, top: t.y, fill: Theme.paper) }
        if let b = bubble {
            fillRound(b.rect, 9, Theme.paper, stroke: Theme.ink)
            // 꼬리: 6px 사각형을 45도 돌린 모양. 가운데가 말풍선 아래 테두리에 놓인다.
            let c = CGPoint(x: b.tailX, y: b.rect.maxY), d: CGFloat = 4.24
            let fill = NSBezierPath(); fill.move(to: CGPoint(x: c.x - d, y: c.y)); fill.line(to: CGPoint(x: c.x, y: c.y - d)); fill.line(to: CGPoint(x: c.x + d, y: c.y)); fill.line(to: CGPoint(x: c.x, y: c.y + d)); fill.close()
            Theme.paper.setFill(); fill.fill()
            let v = NSBezierPath(); v.move(to: CGPoint(x: c.x - d + 1.4, y: c.y)); v.line(to: CGPoint(x: c.x, y: c.y + d - 1.4)); v.line(to: CGPoint(x: c.x + d - 1.4, y: c.y))
            v.lineWidth = 2; Theme.ink.setStroke(); v.stroke()
            Line(b.text, Self.font, Theme.ink).draw(x: b.rect.minX + 8, cy: b.rect.midY, maxWidth: b.rect.width - 16)
        }
    }

    /// 단계 이름표: 종이색, 화면 1pt 남색 테두리, Jua 화면 10pt, 옆 여백 화면 2pt. 검수와 완료 이름표 사이가 26칸이라 여백을 더 줄 수 없다.
    static func signWidth(_ text: String) -> CGFloat { Line(text, font, Theme.ink).width + 8 }
    private func sign(_ text: String, cx: CGFloat, top: CGFloat, fill: NSColor) {
        let l = Line(text, Self.font, Theme.ink), w = Self.signWidth(text), r = CGRect(x: cx - w / 2, y: top, width: w, height: Self.signH)
        fillRound(r, 2, fill, stroke: Theme.ink)
        l.draw(x: r.minX + 4, cy: r.midY)
    }
}

final class SceneView: NSView {
    let base = PixelView(), fx = PixelView(), overlay = SceneOverlay()
    var onScroll: (Int) -> Void = { _ in }
    private var wheel: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        // 픽셀 그림과 글자 층은 480×216 좌표로 그린다. 창에서는 frame 크기(240×108)로 줄어 픽셀 한 칸이 레티나 2px이 된다.
        setBoundsSize(CGSize(width: 480, height: 216))
        for v in [base, fx, overlay] { v.frame = bounds; addSubview(v) }
        base.setAccessibilityElement(true); base.setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        // 트랙패드는 작은 값이 여러 번 온다. 모아서 층 하나씩 옮긴다.
        wheel += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 20 : event.scrollingDeltaY
        if abs(wheel) >= 1 { onScroll(wheel > 0 ? -1 : 1); wheel = 0 }
        if event.phase == .ended { wheel = 0 }
    }
}

// MARK: 목록

/// 목록 보기. 종이색 바탕에 두 단(5:6), 넓은 구역은 두 단을 모두 쓴다.
final class ListDoc: NSView {
    private struct Item { var rect: CGRect; var face: FloorAgent?; var text: NSAttributedString; var line: Bool }
    private var heads: [(String, CGPoint)] = []
    private var items: [Item] = []
    /// 직접 그린 글은 화면 낭독기에 보이지 않는다. 제목과 줄을 글자 요소로 내보낸다.
    private var spoken: [NSAccessibilityElement] = []
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? { "목록" }
    override func accessibilityChildren() -> [Any]? { spoken }

    static func rowPlain(_ r: ListRow) -> String {
        ([r.title, r.subtitle] + r.tags.map { Optional($0.text) } + [r.meta]).compactMap { $0 }.joined(separator: ", ")
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    func update(_ m: ListModel, width: CGFloat, minHeight: CGFloat) {
        heads = []; items = []
        var say: [(String, CGRect)] = []
        // 폭이 360pt보다 좁으면 한 단으로 쓴다.
        let one = width < 360
        let inner = width - 16, colW = [(inner - 14) * 5 / 11, (inner - 14) * 6 / 11]
        var y: CGFloat = 6, col = 0, rowBottom: CGFloat = 6
        for var s in m.sections {
            if one { s.wide = true }
            // 넓은 구역은 새 줄에서 시작한다.
            if s.wide && col == 1 { y = rowBottom + 8; col = 0 }
            let x = col == 0 ? 8 : 8 + colW[0] + 14, w = s.wide ? inner : colW[col]
            heads.append((s.title, CGPoint(x: x, y: y)))
            say.append((s.title, CGRect(x: x, y: y, width: w, height: 16)))
            var cy = y + 15.6 + 3
            for (i, r) in s.rows.enumerated() {
                if i > 0 { cy += 4 }
                let text = ListDoc.rowText(r), tx = r.face == nil ? 0 : 30
                let h = ceil(text.boundingRect(with: CGSize(width: w - CGFloat(tx), height: 10_000), options: [.usesLineFragmentOrigin]).height)
                let rh = 1.5 + 4 + max(h, r.face == nil ? 0 : 24)
                items.append(Item(rect: CGRect(x: x, y: cy, width: w, height: rh), face: r.face, text: text, line: true))
                say.append((ListDoc.rowPlain(r), CGRect(x: x, y: cy, width: w, height: rh)))
                cy += rh
            }
            rowBottom = max(rowBottom, cy)
            if s.wide || col == 1 { col = 0; y = rowBottom + 8 } else { col = 1 }
        }
        setFrameSize(CGSize(width: width, height: max(minHeight, rowBottom + 8)))
        spoken = say.map { text, r in
            let e = NSAccessibilityElement()
            e.setAccessibilityRole(.staticText); e.setAccessibilityValue(text); e.setAccessibilityParent(self)
            // 부모 좌표는 아래에서 위로 센다.
            e.setAccessibilityFrameInParentSpace(CGRect(x: r.minX, y: frame.height - r.maxY, width: r.width, height: r.height))
            return e
        }
        needsDisplay = true
    }

    static func rowText(_ r: ListRow) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let p = NSMutableParagraphStyle(); p.lineSpacing = 2
        func add(_ t: String, _ f: NSFont, _ c: NSColor) { s.append(NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: p])) }
        add(r.title, Theme.jua(12), Theme.ink)
        if let sub = r.subtitle { add(" " + sub, Theme.body(11), Theme.ink) }
        for t in r.tags {
            add(" ", Theme.body(11), Theme.ink)
            let a = NSTextAttachment(); a.image = tagImage(t)
            a.bounds = CGRect(x: 0, y: -3, width: a.image!.size.width, height: a.image!.size.height)
            s.append(NSAttributedString(attachment: a))
        }
        if let m = r.meta { add("\n" + m, Theme.body(10), Theme.paperSub) }
        return s
    }

    /// 꼬리표: 1.5pt 테두리, 모서리 2pt, Jua 10.
    static func tagImage(_ t: ListTag) -> NSImage {
        let fg = t.style == .halt ? Theme.paper : Theme.ink, bg: NSColor? = t.style == .turn ? Theme.pink : t.style == .halt ? Theme.ink : nil
        let l = Line(t.text, Theme.jua(10), fg), size = CGSize(width: l.width + 10, height: 15)
        let img = NSImage(size: size, flipped: true) { r in
            fillRound(r, 2, bg, stroke: Theme.ink, width: 1.5)
            l.draw(x: 5, cy: r.midY)
            return true
        }
        img.accessibilityDescription = t.text
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.paper.setFill(); bounds.fill()
        for (t, p) in heads { Line(t, Theme.jua(13), Theme.ink).draw(x: p.x, cy: p.y + 7.8) }
        for it in items {
            Theme.paperLine.setFill(); CGRect(x: it.rect.minX, y: it.rect.minY, width: it.rect.width, height: 1.5).fill()
            var tx = it.rect.minX
            if let f = it.face {
                drawPixels(SceneRenderer.icon(.face(f.coat, f.pose)), in: CGRect(x: tx, y: it.rect.minY + 5.5, width: 24, height: 24)); tx += 30
            }
            it.text.draw(with: CGRect(x: tx, y: it.rect.minY + 5.5, width: it.rect.maxX - tx, height: it.rect.height), options: [.usesLineFragmentOrigin])
        }
        if window?.firstResponder === self { fillRound(visibleRect.insetBy(dx: 1, dy: 1), 0, nil, stroke: Theme.ink) }
    }

    override func keyDown(with event: NSEvent) {
        guard let clip = enclosingScrollView?.contentView else { return super.keyDown(with: event) }
        let page = clip.bounds.height - 24, y = clip.bounds.minY
        let to: CGFloat? = switch event.keyCode {
        case 125: y + 24; case 126: y - 24; case 121, 49: y + page; case 116: y - page; case 115: 0; case 119: .greatestFiniteMagnitude
        default: nil
        }
        guard let to else { return super.keyDown(with: event) }
        clip.scroll(to: CGPoint(x: 0, y: max(0, min(to, frame.height - clip.bounds.height))))
        enclosingScrollView?.reflectScrolledClipView(clip)
        needsDisplay = true
    }
}

final class ListPane: NSScrollView {
    let doc = ListDoc()
    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true; scrollerStyle = .overlay; drawsBackground = true; backgroundColor = Theme.paper
        documentView = doc
        setAccessibilityLabel("글자 목록")
    }
    required init?(coder: NSCoder) { nil }

    func update(_ m: ListModel) {
        let top = contentView.bounds.minY
        doc.update(m, width: bounds.width, minHeight: bounds.height)
        contentView.scroll(to: CGPoint(x: 0, y: min(top, max(0, doc.frame.height - bounds.height))))
        reflectScrolledClipView(contentView)
    }
}
