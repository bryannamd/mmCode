import AppKit
import MonitorCore
import MonitorScene

/// 모든 화면에 같은 위치의 뒤로 가기와 보기 전환을 둔다.
final class RoofView: FocusHost {
    static let height: CGFloat = 45
    let building = PanelButton(.nav, "전체", label: "전체 프로젝트로 돌아가기")
    let list = PanelButton(.nav, "기록", label: "작업 기록 보기")
    let map = PanelButton(.nav, "공간 보기", label: "공간 보기")
    private var title = ""
    private var demo = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        [building, list, map].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        focusColor = Theme.ink
    }
    required init?(coder: NSCoder) { nil }

    func update(_ m: RoofModel, office: Bool, listOn: Bool, mapOn: Bool) {
        title = office ? m.title : "작업 모니터"
        demo = m.isDemo
        building.isHidden = !office
        building.alarm = m.alert != nil
        building.toolTip = m.alert.map { "다른 프로젝트 · " + $0.long } ?? "전체 프로젝트로 돌아가기"
        building.setAccessibilityLabel(building.toolTip)
        list.title = listOn ? "현황" : "기록"
        map.title = mapOn ? "현황" : "공간 보기"
        list.on = listOn
        map.on = mapOn
        list.isHidden = !office
        list.setAccessibilityLabel(listOn ? "작업 현황 보기" : "작업 기록 보기")
        map.setAccessibilityLabel(mapOn ? "작업 현황 보기" : "픽셀 공간 보기")
        building.frame = CGRect(x: 8, y: 8, width: 40, height: 29)
        map.frame = CGRect(x: bounds.width - 80, y: 8, width: 66, height: 29)
        list.frame = CGRect(x: map.frame.minX - 44, y: 8, width: 40, height: 29)
        setAccessibilityLabel(title + (demo ? ", 예시" : ""))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.surface.setFill()
        bounds.fill()
        let x: CGFloat = building.isHidden ? 16 : building.frame.maxX + 8
        let end = (list.isHidden ? map : list).frame.minX - 8
        let name = Line(title, Theme.body(15, .bold), Theme.ink)
        let maxWidth = max(1, end - x - (demo ? 29 : 0))
        name.draw(x: x, cy: bounds.midY, maxWidth: maxWidth)
        if demo { Line("예시", Theme.body(11), Theme.paperSub).draw(x: x + min(name.width, maxWidth) + 6, cy: bounds.midY) }
        Theme.paperLine.setFill()
        CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5).fill()
        drawFocus()
    }
}

// MARK: 지반

struct GroundSpec {
    /// `focus`: 지반에 초점이 있을 때 먼저 받을 버튼(예: 중단 확인의 "취소").
    struct Button { var label: String; var aria: String; var primary = false; var disabled = false; var close = false; var focus = false; var command: GroundAction?; var press: () -> Void }
    /// 한 줄 입력칸. 제목·설명 대신 이름표와 입력칸을 그린다. `id`가 바뀌면 글을 비우고 초점을 준다.
    struct Field { var id: String; var label: String; var placeholder: String; var submit: (String) -> Void; var cancel: () -> Void }
    var turn: Bool
    var icon: GroundIcon
    var title: String
    var pill: String?
    var detail: String
    var buttons: [Button]
    var field: Field?
    var connection: PostCat?
    var question: ScreenQuestion?
}

final class GroundView: FocusHost {
    private var spec: GroundSpec?
    private(set) var buttons: [PanelButton] = []
    private let letter = NSScrollView()
    private let textPage = FlippedPage()
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var stamp = CGRect.zero
    private var overflow: [GroundSpec.Button] = []
    private weak var openMenu: NSMenu?
    private var project: String?

    private func menuChanged(_ next: GroundSpec, project nextProject: String?) -> Bool {
        guard let old = spec, project == nextProject, old.title == next.title, old.question == next.question,
              old.buttons.count == next.buttons.count else { return true }
        return zip(old.buttons, next.buttons).contains { a, b in
            a.command != b.command || a.label != b.label || a.aria != b.aria || a.disabled != b.disabled
        }
    }
    let input = InputBox()

    private final class FlippedPage: NSView {
        override var isFlipped: Bool { true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        letter.drawsBackground = false
        letter.borderType = .noBorder
        letter.scrollerStyle = .overlay
        letter.autohidesScrollers = true
        letter.documentView = textPage
        addSubview(letter)
        for label in [heading, detail] {
            label.isSelectable = true
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            textPage.addSubview(label)
        }
        input.isHidden = true
        addSubview(input)
    }
    required init?(coder: NSCoder) { nil }

    private func place(_ label: NSTextField, text: String, font: NSFont, color: NSColor, top: CGFloat, width: CGFloat) -> CGFloat {
        label.stringValue = text
        label.font = font
        label.textColor = color
        let size = label.cell!.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: 10000))
        label.frame = CGRect(x: 0, y: top, width: width, height: ceil(size.height))
        label.toolTip = text
        return label.frame.maxY
    }

    func update(_ g: GroundSpec, project nextProject: String?) {
        if let openMenu, menuChanged(g, project: nextProject) { openMenu.cancelTrackingWithoutAnimation() }
        project = nextProject
        let focusedLabel = buttons.first(where: { $0.isFocused })?.accessibilityLabel()
        let hadFocus = focusedLabel != nil || input.editing
        let changed = spec?.title != g.title || spec?.detail != g.detail || spec?.pill != g.pill || spec?.field?.id != g.field?.id
        spec = g
        focusColor = Theme.ink
        let inset: CGFloat = 16, inner = bounds.width - 2 * inset
        stamp = CGRect(x: bounds.width - 76, y: 13, width: 62, height: 52)
        let title = g.field?.label ?? g.title
        let metadata = [g.pill, g.detail.isEmpty ? nil : g.detail].compactMap { $0 }.joined(separator: " · ")
        let textWidth = inner - 69
        let h = place(heading, text: title, font: Theme.body(19, .bold), color: Theme.ink, top: 0, width: textWidth)
        let bottom = metadata.isEmpty ? h : place(detail, text: metadata, font: Theme.body(13), color: Theme.paperSub, top: h + 5, width: textWidth)
        detail.isHidden = metadata.isEmpty
        let visible = min(108, bottom)
        letter.hasVerticalScroller = bottom > visible
        letter.frame = CGRect(x: inset, y: 14, width: textWidth + 2, height: visible)
        textPage.frame = CGRect(x: 0, y: 0, width: textWidth, height: bottom)
        if changed { textPage.scroll(.zero) }
        var top = max(stamp.maxY, letter.frame.maxY) + 8
        if let f = g.field {
            input.frame = CGRect(x: inset, y: top, width: inner, height: 27)
            input.isHidden = false
            input.show(f)
            top += 32
        } else { input.hide() }
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        var x = inset
        for action in inlineActions(g.buttons, width: inner) {
            let b = PanelButton(action.close ? .close : action.primary ? .primary : .outline, action.label, label: action.aria, onPress: action.press)
            b.turn = g.turn
            b.disabled = action.disabled
            b.focus = action.focus
            b.toolTip = action.aria
            let width = min(inner, b.fitSize.width)
            if x > inset && x + width > bounds.width - inset { x = inset; top += 30 }
            b.frame = CGRect(x: x, y: top, width: width, height: 31)
            addSubview(b)
            buttons.append(b)
            x += width + 5
        }
        if !buttons.isEmpty { top += 32 }
        setFrameSize(CGSize(width: bounds.width, height: top + 5))
        setAccessibilityLabel(title)
        if input.fresh {
            input.fresh = false
            window?.makeFirstResponder(input.field)
        } else if hadFocus, !input.editing {
            let next = buttons.first { $0.accessibilityLabel() == focusedLabel && !$0.disabled }
                ?? buttons.first { $0.focus && !$0.disabled } ?? buttons.first { !$0.disabled }
            if let next { window?.makeFirstResponder(next) }
        }
        needsDisplay = true
    }

    /// Keep the whole reply row reachable without growing the window for every option.
    private func inlineActions(_ actions: [GroundSpec.Button], width: CGFloat) -> [GroundSpec.Button] {
        overflow = []
        let close = actions.filter(\.close)
        let choices = actions.filter { !$0.close }
        func widthOf(_ list: [GroundSpec.Button]) -> CGFloat {
            let labels = list.map { action in
                action.close ? 24 : max(32, Line(action.label, Theme.body(13, .semibold), .black).width + 20)
            }
            return labels.reduce(0, +) + CGFloat(max(0, labels.count - 1)) * 5
        }
        guard widthOf(actions) > width, !choices.isEmpty else { return actions }
        let more = GroundSpec.Button(label: "더 보기", aria: "나머지 선택지 보기") { [weak self] in self?.showOptions() }
        var first = choices
        while !first.isEmpty && widthOf(first + [more] + close) > width { first.removeLast() }
        overflow = Array(choices.dropFirst(first.count))
        return first + [more] + close
    }

    private func showOptions() {
        guard let anchor = buttons.first(where: { $0.accessibilityLabel() == "나머지 선택지 보기" }) else { return }
        let menu = NSMenu()
        openMenu = menu
        menu.autoenablesItems = false
        for action in overflow {
            let item = menu.addItem(withTitle: action.label, action: #selector(pickOption(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.isEnabled = !action.disabled
        }
        menu.popUp(positioning: nil, at: CGPoint(x: anchor.frame.minX, y: anchor.frame.maxY), in: self)
    }

    @objc private func pickOption(_ item: NSMenuItem) {
        guard let action = item.representedObject as? GroundSpec.Button, !action.disabled else { return }
        action.press()
    }

    func press(_ label: String) { buttons.first { $0.title == label && !$0.disabled }?.onPress() }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = spec else { return }
        let stock = g.turn ? NSColor(hex: 0xffeee7) : NSColor(hex: 0xe8f1e4)
        stock.setFill()
        bounds.fill()
        let color = g.turn ? Theme.postalRed : Theme.ink2
        if let connection = g.connection {
            connection.draw(at: CGPoint(x: stamp.midX - 11, y: stamp.midY - 9), color: color)
        } else {
            // 책상 위 동물은 상황을 전한 담당자다. 담당자가 없으면 안내 고양이가 나온다.
            let character: GroundIcon
            switch g.icon {
            case .building, .bell: character = .face(.tabby, g.turn ? .ask : .wait)
            default: character = g.icon
            }
            if case .face(let coat, let pose) = character {
                drawPixels(SceneRenderer.portrait(coat, pose: pose), in: CGRect(x: stamp.midX - 26, y: stamp.minY, width: 52, height: 44))
                let laptop = CGRect(x: stamp.midX - 13, y: stamp.minY + 32, width: 26, height: 13)
                fillRound(laptop, 2.5, g.turn ? NSColor(hex: 0xfbc6b9) : Theme.sage, stroke: Theme.ink, width: 1.5)
                fillRound(CGRect(x: laptop.midX - 2, y: laptop.midY - 1, width: 4, height: 2), 1, Theme.ink)
            } else {
                drawPixels(SceneRenderer.icon(character), in: CGRect(x: stamp.midX - 18, y: stamp.minY + 6, width: 36, height: 36))
            }
            let desk = CGRect(x: stamp.minX + 3, y: stamp.minY + 43, width: stamp.width - 6, height: 3)
            fillRound(desk, 1.5, color)
            for x in [desk.minX + 6, desk.maxX - 8] {
                fillRound(CGRect(x: x, y: desk.maxY, width: 2, height: 4), 1, color)
            }
        }
        drawFocus()
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
        fillRound(bounds, 7, .white, stroke: Theme.paperSub, width: 1)
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
        // 한 줄에서 기록 내용을 읽을 수 있도록 패널 폭에서는 한 단으로 쓴다.
        let one = width < 520
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
        add(r.title, Theme.body(14, .semibold), Theme.ink)
        if let sub = r.subtitle { add(" " + sub, Theme.body(13), Theme.ink) }
        for t in r.tags {
            add(" ", Theme.body(11), Theme.ink)
            let a = NSTextAttachment(); a.image = tagImage(t)
            a.bounds = CGRect(x: 0, y: -3, width: a.image!.size.width, height: a.image!.size.height)
            s.append(NSAttributedString(attachment: a))
        }
        if let m = r.meta { add("\n" + m, Theme.body(12), Theme.paperSub) }
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
        for (t, p) in heads { Line(t, Theme.body(14, .semibold), Theme.ink).draw(x: p.x, cy: p.y + 7.8) }
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
