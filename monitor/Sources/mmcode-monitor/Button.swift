import AppKit

/// 패널의 모든 버튼. 마우스, 키보드(스페이스·리턴), 화면 낭독기로 누를 수 있다.
/// 초점 테두리는 버튼 밖에 그려야 해서 부모(FocusHost)가 그린다.
class PanelButton: NSView {
    enum Style { case nav, primary, outline, close, hit }

    var style: Style
    var title: String
    /// 지반이 분홍일 때 색을 뒤집는다.
    var turn = false
    var on = false { didSet { needsDisplay = true } }
    /// 지붕 버튼을 분홍으로 칠한다. 다른 층에 나설 일이 있다는 표시다.
    var alarm = false { didSet { needsDisplay = true } }
    var disabled = false
    /// 지반에 초점이 있을 때 먼저 받는다.
    var focus = false
    /// 보이는 영역. 클릭 영역(frame)보다 작을 수 있다.
    var visual: CGRect = .zero
    var onPress: () -> Void = {}
    private var hover = false

    init(_ style: Style, _ title: String, label: String? = nil, onPress: @escaping () -> Void = {}) {
        self.style = style; self.title = title; self.onPress = onPress
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label ?? title)
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { !disabled }
    override var canBecomeKeyView: Bool { !disabled && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool { superview?.needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { superview?.needsDisplay = true; return true }
    var isFocused: Bool { window?.isKeyWindow == true && window?.firstResponder === self }

    override func accessibilityPerformPress() -> Bool { press(); return true }
    override func isAccessibilityEnabled() -> Bool { !disabled }
    override func accessibilityValue() -> Any? { style == .hit || style == .nav ? (on ? "선택됨" : nil) : nil }

    private func press() { if !disabled { onPress() } }

    override func mouseDown(with event: NSEvent) {
        guard !disabled else { return }
        // 버튼 안에서 놓았을 때만 누른 것으로 친다.
        while let e = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if e.type == .leftMouseUp {
                if bounds.contains(convert(e.locationInWindow, from: nil)) { press() }
                return
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if [36, 49, 76].contains(event.keyCode) { press() } else { super.keyDown(with: event) }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    /// 글자 폭에 맞춘 보이는 크기.
    var fitSize: CGSize {
        switch style {
        case .nav: return CGSize(width: Line(title, Theme.jua(11), .black).width + 12, height: 18)
        case .primary, .outline: return CGSize(width: max(32, Line(title, Theme.jua(12), .black).width + 20), height: 24)
        case .close: return CGSize(width: 24, height: 24)
        case .hit: return visual.size
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = visual == .zero ? bounds : visual
        let fg = turn ? Theme.ink : Theme.paper, bg = turn ? Theme.pink : Theme.ink
        let alpha: CGFloat = disabled ? 0.5 : 1
        switch style {
        case .nav:
            fillRound(r, 5, on ? Theme.paper : alarm ? Theme.pink : hover ? Theme.ink3 : Theme.ink2)
            Line(title, Theme.jua(11), on || alarm ? Theme.ink : Theme.paper).draw(x: r.minX + 6, cy: r.midY)
        case .primary:
            fillRound(r, 7, fg.withAlphaComponent(alpha), stroke: fg.withAlphaComponent(alpha))
            Line(title, Theme.jua(12), bg.withAlphaComponent(alpha)).draw(x: r.minX + 10, cy: r.midY, maxWidth: r.width - 20)
        case .outline:
            let h = turn ? Theme.ink.withAlphaComponent(0.14) : Theme.paper.withAlphaComponent(0.16)
            fillRound(r, 7, hover && !disabled ? h : nil, stroke: fg.withAlphaComponent(alpha))
            Line(title, Theme.jua(12), fg.withAlphaComponent(alpha)).draw(x: r.minX + 10, cy: r.midY, maxWidth: r.width - 20)
        case .close:
            if hover { fillRound(r, 7, turn ? Theme.ink.withAlphaComponent(0.14) : Theme.paper.withAlphaComponent(0.16)) }
            let p = NSBezierPath(), o = CGPoint(x: r.midX - 4, y: r.midY - 4)
            p.move(to: CGPoint(x: o.x, y: o.y)); p.line(to: CGPoint(x: o.x + 8, y: o.y + 8))
            p.move(to: CGPoint(x: o.x + 8, y: o.y)); p.line(to: CGPoint(x: o.x, y: o.y + 8))
            p.lineWidth = 2; p.lineCapStyle = .round; fg.setStroke(); p.stroke()
        case .hit:
            if hover { fillRound(r, 6, Theme.paper.withAlphaComponent(0.28)) }
            if on {
                fillRound(r, 6, nil, stroke: Theme.paper)
                fillRound(r.insetBy(dx: -2, dy: -2), 8, nil, stroke: Theme.ink)
            }
        }
    }
}

/// 자식 버튼의 초점 테두리를 그리는 부모. 테두리는 버튼 밖 2px 간격, 2px 굵기다.
class FocusHost: NSView {
    override var isFlipped: Bool { true }
    /// 바탕이 남색이면 종이색, 종이나 분홍이면 남색.
    var focusColor = Theme.paper

    func drawFocus() {
        for case let b as PanelButton in subviews where b.isFocused && !b.isHidden {
            let r = (b.visual == .zero ? b.bounds : b.visual).offsetBy(dx: b.frame.minX, dy: b.frame.minY)
            if b.style == .hit {
                // 장면의 클릭 영역: 종이색 2px 선 바깥에 남색 4px 띠.
                fillRound(r.insetBy(dx: -4, dy: -4), 10, nil, stroke: Theme.ink, width: 4)
                fillRound(r, 6, nil, stroke: Theme.paper)
            } else {
                fillRound(r.insetBy(dx: -4, dy: -4), 8, nil, stroke: focusColor)
            }
        }
    }
}
