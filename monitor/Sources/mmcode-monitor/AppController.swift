import AppKit
import MonitorCore
import MonitorScene

/// 테두리 없는 패널. 키보드(Tab, Esc, 화살표)를 받으려면 key 창이 되어야 한다.
final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 메뉴 막대 아이콘, 패널 창, 움직임 타이머를 맡는다.
final class AppController: NSObject, NSApplicationDelegate {
    private let args: Args
    private let store: Store
    private static let size = PanelView.size
    /// 패널 모서리(pt).
    static let radius: CGFloat = 10
    private let panel = PanelView(frame: CGRect(x: 2, y: 2, width: size.width, height: size.height))
    private var window: PanelWindow!
    private var item: NSStatusItem!
    private var frameTimer: Timer?
    private var outside: Any?
    private var iconState: PostCat?

    init(_ args: Args) {
        self.args = args
        store = Store(demo: args.demo)
        super.init()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        Fonts.register()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("mmCode 모니터")

        window = PanelWindow(contentRect: CGRect(x: 0, y: 0, width: Self.size.width + 4, height: Self.size.height + 4), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .popUpMenu; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.autorecalculatesKeyViewLoop = true
        // 패널 테두리 2px는 패널 바깥에 둔다(시안의 box-shadow 0 0 0 2px).
        let frame = NSView(frame: CGRect(x: 0, y: 0, width: Self.size.width + 4, height: Self.size.height + 4))
        frame.wantsLayer = true
        frame.layer?.cornerRadius = 2 + Self.radius; frame.layer?.masksToBounds = true
        panel.wantsLayer = true; panel.layer?.cornerRadius = Self.radius; panel.layer?.masksToBounds = true
        frame.addSubview(panel)
        window.contentView = frame
        window.initialFirstResponder = panel
        edgeColor()
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.close() }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in self?.syncTimer() }

        panel.onClose = { [weak self] in self?.close() }
        panel.onFocus = { [weak self] root in self?.store.setFocus(root) }
        store.onChange = { [weak self] in self?.dataChanged() }
        panel.onHeightChange = { [weak self] height in
            guard let self else { return }
            var rect = window.frame
            rect.origin.y += rect.height - height - 4
            rect.size.height = height + 4
            window.setFrame(rect, display: window.isVisible)
        }
        panel.onSceneVisibilityChange = { [weak self] in self?.syncTimer() }
        configure(panel, args, store)
        updateIcon()
        store.start()
        if args.open { show() }
        if let t = args.exitAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                print(memoryLine()); fflush(stdout)
                self?.store.stop()
                exit(0)
            }
        }
    }

    func applicationWillTerminate(_ n: Notification) { store.stop() }

    private func dataChanged() {
        panel.world = store.world; panel.hcMissing = store.hcMissing; panel.hcDown = store.hcDown; panel.loaded = store.loaded
        panel.noteSaid()
        panel.recordsChanged()
        updateIcon()
        // 닫혀 있으면 그리지 않는다. 열 때 다시 그린다.
        if window.isVisible { panel.reload() }
    }

    // MARK: 메뉴 막대 아이콘

    private func updateIcon() {
        let state = PostCat.state(store)
        guard state != iconState else { return }
        iconState = state
        item.button?.image = state.image
        item.button?.setAccessibilityValue(state.description)
        item.button?.toolTip = "mmCode · " + state.description
    }

    // MARK: 패널 열고 닫기

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu; item.button?.performClick(nil); item.menu = nil
            return
        }
        window.isVisible ? close() : show()
    }

    private func show() {
        if let b = item.button, let bw = b.window {
            let r = bw.convertToScreen(b.convert(b.bounds, to: nil))
            let vis = (bw.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let x = max(vis.minX + 4, min(r.midX - (Self.size.width + 4) / 2, vis.maxX - Self.size.width - 8))
            window.setFrameTopLeftPoint(CGPoint(x: x, y: r.minY - 4))
        }
        edgeColor()
        if args.demo == nil && args.view == nil { panel.openOverview() } else { panel.reload() }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(panel)
        window.invalidateShadow()
        outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        syncTimer()
    }

    private func close() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        if let o = outside { NSEvent.removeMonitor(o); outside = nil }
        syncTimer()
    }

    /// 다크 모드 바탕에서는 남색 테두리가 묻혀 ink-3을 쓴다(시안의 --edge).
    private func edgeColor() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        window.contentView?.layer?.backgroundColor = (dark ? Theme.ink3 : Theme.ink).cgColor
    }

    // MARK: 움직임

    /// 패널이 보이고 가려지지 않았을 때만 프레임을 바꾼다(0.34초, 약 3Hz). 움직임 줄이기 설정이면 멈춘다.
    private func syncTimer() {
        let run = !panel.scene.isHidden && window.isVisible && window.occlusionState.contains(.visible) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if run, frameTimer == nil {
            frameTimer = Timer.scheduledTimer(withTimeInterval: 0.34, repeats: true) { [weak self] _ in self?.panel.tick() }
        } else if !run {
            frameTimer?.invalidate(); frameTimer = nil
        }
    }
}
