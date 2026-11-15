import AppKit
import MonitorCore
import MonitorScene

// 패널의 세 층: 지붕(28), 장면(216) 또는 목록, 지반(56). 값은 시안의 CSS를 옮긴다.

// MARK: 지붕

final class RoofView: FocusHost {
    let building = PanelButton(.nav, "건물", label: "건물 보기")
    let list = PanelButton(.nav, "목록", label: "목록 보기")
    let alert = PanelButton(.pill, "")
    private var model: RoofModel?
    private var nameX: CGFloat = 0, nameMax: CGFloat = 0, cellsX: CGFloat = 0, countX: CGFloat = 0, demoRect = CGRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        [building, list, alert].forEach(addSubview)
    }
    required init?(coder: NSCoder) { nil }

    func update(_ m: RoofModel, buildingOn: Bool, listOn: Bool) {
        model = m
        building.on = buildingOn; list.on = listOn
        building.setAccessibilityLabel(buildingOn ? "건물 보기 닫기" : "건물 보기")
        list.setAccessibilityLabel(listOn ? "목록 보기 닫기" : "목록 보기")
        let W = bounds.width
        var right = W - 8
        if m.isDemo {
            let w = Line("예시", Theme.body(11), .black).width + 10
            demoRect = CGRect(x: right - w, y: 14 - 8, width: w, height: 16); right -= w + 8
        }
        place(list, right: right); right = list.frame.minX + 3 - 8
        building.frame = CGRect(x: 8 - 3, y: 4 - 4, width: building.fitSize.width + 6, height: 40)
        building.visual = CGRect(x: 3, y: 4, width: building.fitSize.width, height: 20)
        nameX = building.frame.maxX - 3 + 8
        let cellsW = m.cells.isEmpty ? 0 : CGFloat(m.cells.count) * 13 - 3 + 8
        let countW = m.count.map { Line($0, Theme.body(11), .black).width + 8 } ?? 0
        let nameW = Line(m.title, Theme.jua(16), .black).width
        alert.isHidden = m.alert == nil
        if let a = m.alert {
            // 넓을 때 긴 문구, 모자라면 짧은 문구(시안의 440px 이하 규칙과 같은 뜻).
            alert.title = a.long
            if right - alert.fitSize.width - 8 < nameX + nameW + cellsW + countW { alert.title = a.short }
            alert.setAccessibilityLabel("다른 층 알림: \(a.long). 건물 보기 열기")
            place(alert, right: right); right = alert.frame.minX + 3 - 8
        }
        nameMax = max(40, right - nameX - cellsW - countW)
        cellsX = nameX + min(nameW, nameMax) + 8
        countX = cellsX + cellsW
        needsDisplay = true
    }

    private func place(_ b: PanelButton, right: CGFloat) {
        let s = b.fitSize, y = (28 - s.height) / 2
        // 클릭 영역은 위로 4px, 아래로 16px, 옆으로 3px 넓힌다.
        b.frame = CGRect(x: right - s.width - 3, y: y - 4, width: s.width + 6, height: s.height + 20)
        b.visual = CGRect(x: 3, y: 4, width: s.width, height: s.height)
        b.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.ink.setFill(); bounds.fill()
        drawFocus()
        guard let m = model else { return }
        Line(m.title, Theme.jua(16), Theme.paper).draw(x: nameX, cy: 14, maxWidth: nameMax)
        for (i, d) in m.cells.enumerated() {
            let r = CGRect(x: cellsX + CGFloat(i) * 13, y: 10, width: 10, height: 8)
            (d ? Theme.boxDone : Theme.box).setFill(); r.fill()
            (d ? Theme.boxDone2 : Theme.box2).setFill(); CGRect(x: r.minX, y: r.maxY - 2, width: 10, height: 2).fill()
        }
        if let c = m.count { Line(c, Theme.body(11), Theme.onInkSub).draw(x: countX, cy: 14) }
        if m.isDemo {
            fillRound(demoRect, 3, nil, stroke: Theme.ink3, width: 1)
            Line("예시", Theme.body(11), Theme.onInkSub).draw(x: demoRect.minX + 5, cy: demoRect.midY)
        }
    }
}

// MARK: 지반

struct GroundSpec {
    struct Button { var label: String; var aria: String; var primary = false; var disabled = false; var close = false; var press: () -> Void }
    var turn: Bool
    var icon: GroundIcon
    var title: String
    var pill: String?
    var detail: String
    var buttons: [Button]
}

final class GroundView: FocusHost {
    private var spec: GroundSpec?
    private var buttons: [PanelButton] = []
    private var textMax: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { nil }

    func update(_ g: GroundSpec) {
        let hadFocus = buttons.contains { $0.isFocused }
        spec = g
        focusColor = g.turn ? Theme.ink : Theme.paper
        buttons.forEach { $0.removeFromSuperview() }
        buttons = g.buttons.map { s in
            let b = PanelButton(s.close ? .close : s.primary ? .primary : .outline, s.label, label: s.aria, onPress: s.press)
            b.turn = g.turn; b.disabled = s.disabled
            return b
        }
        // 버튼은 오른쪽 끝(10px 여백)부터 8px 간격. 클릭 영역은 위아래 6px, 옆 2px 넓힌다.
        var right = bounds.width - 10
        for b in buttons.reversed() {
            let s = b.fitSize, pad: CGFloat = b.style == .close ? 6 : 2
            b.frame = CGRect(x: right - s.width - pad, y: 29 - s.height / 2 - 6, width: s.width + pad * 2, height: s.height + 12)
            b.visual = CGRect(x: pad, y: 6, width: s.width, height: s.height)
            right -= s.width + 8
            addSubview(b)
        }
        textMax = (buttons.isEmpty ? bounds.width - 10 : right + 8 - 10) - 56
        setAccessibilityLabel("\(g.title). \(g.pill.map { $0 + ". " } ?? "")\(g.detail)")
        if hadFocus, let f = buttons.first(where: { !$0.disabled }) { window?.makeFirstResponder(f) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = spec else { return }
        let fg = g.turn ? Theme.ink : Theme.paper, sub = g.turn ? Theme.ink : Theme.onInkSub
        (g.turn ? Theme.pink : Theme.ink).setFill(); bounds.fill()
        Theme.ink.setFill(); CGRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
        drawFocus()
        // 얼굴 칸: 36px 원, 종이색, 2px 테두리(평소에는 종이색이라 보이지 않는다). 안의 16px 그림을 32px로.
        let c = CGRect(x: 10, y: 29 - 18, width: 36, height: 36)
        NSGraphicsContext.saveGraphicsState()
        let circle = NSBezierPath(ovalIn: c); Theme.paper.setFill(); circle.fill(); circle.addClip()
        drawPixels(SceneRenderer.icon(g.icon), in: CGRect(x: c.minX + 2, y: c.minY + 2, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        let ring = NSBezierPath(ovalIn: c.insetBy(dx: 1, dy: 1)); ring.lineWidth = 2; (g.turn ? Theme.ink : Theme.paper).setStroke(); ring.stroke()
        // 글 두 줄: Jua 17(줄 높이 20.4)과 시스템 600 11(14.3). 두 줄을 가운데에 모은다.
        let top = 29 - (20.4 + 14.3) / 2, title = Line(g.title, Theme.jua(17), fg)
        var titleMax = textMax
        if let p = g.pill { titleMax = max(60, textMax - Line(p, Theme.body(11, .semibold), .black).width - 21) }
        title.draw(x: 56, cy: top + 10.2, maxWidth: titleMax)
        if let p = g.pill {
            let pl = Line(p, Theme.body(11, .semibold), fg)
            let x = 56 + min(title.width, titleMax) + 6, w = min(pl.width + 15, 56 + textMax - x)
            let r = CGRect(x: x, y: top + 10.2 - 9 - 1, width: w, height: 18)
            fillRound(r, 8, nil, stroke: fg, width: 1.5)
            pl.draw(x: r.minX + 7.5, cy: r.midY, maxWidth: w - 15)
        }
        Line(g.detail, Theme.body(11, .semibold), sub).draw(x: 56, cy: top + 20.4 + 7.15, maxWidth: textMax)
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
final class SceneOverlay: FocusHost {
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
                Line(l.text, Theme.jua(13), Theme.ink).draw(x: r.minX + 7, cy: r.midY + 0.5, maxWidth: r.width - 9)
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
            Line(b.text, Theme.jua(12), Theme.ink).draw(x: b.rect.minX + 9, cy: b.rect.minY + 2 + 1 + 7.5, maxWidth: b.rect.width - 18)
        }
    }

    /// 단계 이름표: 종이색, 2px 남색 테두리, 모서리 2px, Jua 12, 안쪽 여백 1px 6px 0.
    private func sign(_ text: String, cx: CGFloat, top: CGFloat, fill: NSColor) {
        let l = Line(text, Theme.jua(12), Theme.ink), r = CGRect(x: cx - (l.width + 16) / 2, y: top, width: l.width + 16, height: 20)
        fillRound(r, 2, fill, stroke: Theme.ink)
        l.draw(x: r.minX + 8, cy: r.minY + 3 + 7.5)
    }
}

final class SceneView: NSView {
    let base = PixelView(), fx = PixelView(), overlay = SceneOverlay()
    var onScroll: (Int) -> Void = { _ in }
    private var wheel: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        for v in [base, fx, overlay] { v.frame = bounds; v.autoresizingMask = [.width, .height]; addSubview(v) }
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

    func update(_ m: ListModel, width: CGFloat) {
        heads = []; items = []
        var say: [(String, CGRect)] = []
        let inner = width - 24, colW = [(inner - 14) * 5 / 11, (inner - 14) * 6 / 11]
        var y: CGFloat = 8, col = 0, rowBottom: CGFloat = 8
        for s in m.sections {
            // 넓은 구역은 새 줄에서 시작한다.
            if s.wide && col == 1 { y = rowBottom + 8; col = 0 }
            let x = col == 0 ? 12 : 12 + colW[0] + 14, w = s.wide ? inner : colW[col]
            heads.append((s.title, CGPoint(x: x, y: y)))
            say.append((s.title, CGRect(x: x, y: y, width: w, height: 17)))
            var cy = y + 16.8 + 3
            for (i, r) in s.rows.enumerated() {
                if i > 0 { cy += 4 }
                let text = ListDoc.rowText(r), tx = r.face == nil ? 0 : 40
                let h = ceil(text.boundingRect(with: CGSize(width: w - CGFloat(tx), height: 10_000), options: [.usesLineFragmentOrigin]).height)
                let rh = 1.5 + 4 + max(h, r.face == nil ? 0 : 32)
                items.append(Item(rect: CGRect(x: x, y: cy, width: w, height: rh), face: r.face, text: text, line: true))
                say.append((ListDoc.rowPlain(r), CGRect(x: x, y: cy, width: w, height: rh)))
                cy += rh
            }
            rowBottom = max(rowBottom, cy)
            if s.wide || col == 1 { col = 0; y = rowBottom + 8 } else { col = 1 }
        }
        setFrameSize(CGSize(width: width, height: max(216, rowBottom + 12)))
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
        add(r.title, Theme.jua(13), Theme.ink)
        if let sub = r.subtitle { add(" " + sub, Theme.body(12), Theme.ink) }
        for t in r.tags {
            add(" ", Theme.body(12), Theme.ink)
            let a = NSTextAttachment(); a.image = tagImage(t)
            a.bounds = CGRect(x: 0, y: -4, width: a.image!.size.width, height: a.image!.size.height)
            s.append(NSAttributedString(attachment: a))
        }
        if let m = r.meta { add("\n" + m, Theme.body(11), Theme.paperSub) }
        return s
    }

    /// 꼬리표: 1.5px 테두리, 모서리 2px, Jua 11, 줄 높이 14px.
    static func tagImage(_ t: ListTag) -> NSImage {
        let fg = t.style == .halt ? Theme.paper : Theme.ink, bg: NSColor? = t.style == .turn ? Theme.pink : t.style == .halt ? Theme.ink : nil
        let l = Line(t.text, Theme.jua(11), fg), size = CGSize(width: l.width + 13, height: 18)
        let img = NSImage(size: size, flipped: true) { r in
            fillRound(r, 2, bg, stroke: Theme.ink, width: 1.5)
            l.draw(x: 6.5, cy: 1.5 + 1 + 7)
            return true
        }
        img.accessibilityDescription = t.text
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.paper.setFill(); bounds.fill()
        for (t, p) in heads { Line(t, Theme.jua(14), Theme.ink).draw(x: p.x, cy: p.y + 8.4) }
        for it in items {
            Theme.paperLine.setFill(); CGRect(x: it.rect.minX, y: it.rect.minY, width: it.rect.width, height: 1.5).fill()
            var tx = it.rect.minX
            if let f = it.face {
                drawPixels(SceneRenderer.icon(.face(f.coat, f.pose)), in: CGRect(x: tx, y: it.rect.minY + 5.5, width: 32, height: 32)); tx += 40
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
        doc.update(m, width: bounds.width)
        contentView.scroll(to: CGPoint(x: 0, y: min(top, max(0, doc.frame.height - bounds.height))))
        reflectScrolledClipView(contentView)
    }
}
