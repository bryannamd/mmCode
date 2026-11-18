import AppKit
import MonitorScene

/// 개요와 담당자 명단의 행. 프로젝트와 터미널의 고정 ID로 이동한다.
struct ActivityRow: Equatable {
    let id: String
    let title: String
    let detail: String
    let state: String
    let activity: ProjectSummary.Activity
    let face: FloorAgent?
}

private final class ActivityButton: PanelButton {
    let row: ActivityRow

    init(_ row: ActivityRow, press: @escaping () -> Void) {
        self.row = row
        let text = [row.title, row.state, row.detail].filter { !$0.isEmpty }.joined(separator: ", ")
        super.init(.hit, row.title, label: text, onPress: press)
        toolTip = text
    }
    required init?(coder: NSCoder) { nil }

    override func becomeFirstResponder() -> Bool {
        scrollToVisible(bounds)
        needsDisplay = true
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let urgent = row.activity == .attention
        let active = row.activity == .working
        let ink = urgent ? Theme.postalRed : active ? NSColor(hex: 0x216750) : Theme.paperSub
        let wash = urgent ? NSColor(hex: 0xfbe4e0) : active ? NSColor(hex: 0xdceee2) : NSColor(hex: 0xeceee7)
        if hover || on || isFocused {
            fillRound(bounds.insetBy(dx: 5, dy: 2), 8, NSColor(hex: 0xeef3eb), stroke: isFocused ? Theme.ink3 : nil, width: 1.5)
        }
        let portrait = CGRect(x: 15, y: bounds.midY - 16, width: 32, height: 32)
        fillRound(portrait, 11, wash)
        if let face = row.face {
            drawPixels(SceneRenderer.portrait(face.coat, pose: face.pose), in: CGRect(x: portrait.midX - 13, y: portrait.midY - 11, width: 26, height: 22))
        } else {
            drawSymbol("folder", in: portrait, color: ink, pointSize: 15)
        }
        let left: CGFloat = 59
        Line(row.title, Theme.body(14, .semibold), Theme.ink).draw(x: left, cy: 17, maxWidth: bounds.width - left - 29)
        let state = Line(row.state, Theme.body(12, .semibold), ink)
        state.draw(x: left, cy: 37)
        if !row.detail.isEmpty {
            let split = left + state.width + 8
            Theme.paperLine.setFill()
            CGRect(x: split, y: 32, width: 1, height: 10).fill()
            Line(row.detail, Theme.body(12), Theme.paperSub).draw(x: split + 8, cy: 37, maxWidth: max(1, bounds.width - split - 35))
        }
        drawSymbol("chevron.right", in: CGRect(x: bounds.width - 27, y: 15, width: 18, height: 24), color: Theme.paperSub, pointSize: 10)
        Theme.paperLine.setFill()
        CGRect(x: left, y: bounds.height - 0.5, width: bounds.width - left - 15, height: 0.5).fill()
    }
}

func drawSymbol(_ name: String, in rect: CGRect, color: NSColor, pointSize: CGFloat) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))?
        .withSymbolConfiguration(.init(paletteColors: [color])) else { return }
    let size = image.size
    image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

final class ActivityPane: FocusHost, NSSearchFieldDelegate {
    private let scroll = NSScrollView()
    private let page = FocusHost()
    private let find = NSSearchField()
    private let urgentOnly = PanelButton(.nav, "확인 필요")
    private var filteringUrgent = false
    private let empty = NSTextField(labelWithString: "")
    private var rows = [ActivityRow]()
    private var context = "", caption = "", selected: String?
    private var search = ""
    private var rowsDirty = true
    var select: (String) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = page
        find.font = .systemFont(ofSize: 12)
        find.placeholderString = "프로젝트 검색"
        find.setAccessibilityLabel("프로젝트 검색")
        find.delegate = self
        empty.font = Theme.body(13)
        empty.textColor = Theme.paperSub
        urgentOnly.onPress = { [weak self] in
            guard let self else { return }
            filteringUrgent.toggle()
            urgentOnly.on = filteringUrgent
            rebuild(resetScroll: true)
        }
        addSubview(urgentOnly)
        addSubview(find)
        addSubview(scroll)
        page.setAccessibilityElement(true)
        page.setAccessibilityRole(.group)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    func update(_ items: [ActivityRow], title: String, scope: String, selected: String?, maxHeight: CGFloat) {
        let fresh = scope != context
        if fresh || (items.count < 7 && !find.stringValue.isEmpty) {
            find.stringValue = ""
            search = ""
        }
        let count = items.filter { $0.activity == .attention }.count
        urgentOnly.isHidden = scope != "projects" || count == 0
        if fresh || urgentOnly.isHidden { filteringUrgent = false }
        urgentOnly.title = "확인 필요 " + String(count)
        urgentOnly.on = filteringUrgent
        urgentOnly.setAccessibilityLabel("확인이 필요한 프로젝트 " + String(count) + "개만 보기")
        urgentOnly.frame = CGRect(x: 104, y: 6, width: 86, height: 27)
        let useSearch = scope == "projects" && items.count >= 7
        find.isHidden = !useSearch
        let visibleHeight = min(items.count > 5 ? maxHeight - 13 : maxHeight, CGFloat(max(1, items.count)) * 54)
        setFrameSize(CGSize(width: bounds.width, height: 39 + visibleHeight + 5))
        find.frame = CGRect(x: bounds.width - 146, y: 8, width: 131, height: 23)
        scroll.frame = CGRect(x: 0, y: 39, width: bounds.width, height: visibleHeight)
        rowsDirty = rowsDirty || fresh || rows != items || self.selected != selected
        context = scope
        caption = title
        rows = items
        self.selected = selected
        if rowsDirty { rebuild(resetScroll: fresh) }
        needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) {
        search = find.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuild(resetScroll: true)
    }

    private func rebuild(resetScroll: Bool) {
        let focused = (window?.firstResponder as? ActivityButton)?.row.id
        let top = resetScroll ? 0 : scroll.contentView.bounds.minY
        page.subviews.forEach { $0.removeFromSuperview() }
        let matches = rows.filter {
            (!filteringUrgent || $0.activity == .attention) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
        let h: CGFloat = 54
        page.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.contentSize.height, CGFloat(matches.count) * h))
        var restore: ActivityButton?
        for (i, row) in matches.enumerated() {
            let button = ActivityButton(row) { [weak self] in self?.select(row.id) }
            button.frame = CGRect(x: 0, y: CGFloat(i) * h, width: page.bounds.width, height: h)
            button.on = row.id == selected
            page.addSubview(button)
            if row.id == focused { restore = button }
        }
        if matches.isEmpty {
            empty.stringValue = search.isEmpty ? "연결된 담당자가 없어요" : "일치하는 프로젝트가 없어요"
            empty.frame = CGRect(x: 15, y: 12, width: page.bounds.width - 30, height: 22)
            page.addSubview(empty)
        }
        scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, min(top, page.bounds.height - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
        if let restore { window?.makeFirstResponder(restore) }
        page.setAccessibilityLabel("\(caption), \(matches.count)개")
        rowsDirty = false
    }

    func move(_ direction: Int) {
        let buttons = page.subviews.compactMap { $0 as? ActivityButton }
        guard !buttons.isEmpty else { return }
        let index = buttons.firstIndex { $0 === window?.firstResponder }
        let next = max(0, min(buttons.count - 1, (index ?? (direction > 0 ? -1 : buttons.count)) + direction))
        window?.makeFirstResponder(buttons[next])
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.surface.setFill()
        bounds.fill()
        Line(caption, Theme.body(14, .bold), Theme.ink).draw(x: 15, cy: 21)
        let x = 22 + Line(caption, Theme.body(14, .bold), Theme.ink).width
        Line(String(rows.count), Theme.body(13, .semibold), Theme.paperSub).draw(x: x, cy: 21)
    }
}
