import AppKit
import MonitorCore
import MonitorScene

// 메뉴 막대 앱. 사용법:
//   mmcode-monitor [--demo <이름>] [--open] [--exit-after <초>]
//   mmcode-monitor --snapshot <png> [--demo <이름>] [--view office|building|list] [--day|--night] [--select actor[:번호]|box] [--press <지반 버튼 이름>]

struct Args {
    var demo: Demo?, snapshot: String?, view: String?, night: Bool?, select: String?, press: String?, exitAfter: Double?, open = false

    init(_ a: [String]) {
        var i = 1
        func next() -> String? { i += 1; return i < a.count ? a[i] : nil }
        while i < a.count {
            switch a[i] {
            case "--demo": demo = next().flatMap(Demo.init(rawValue:)); if demo == nil { Args.fail("--demo 값: \(Demo.allCases.map(\.rawValue).joined(separator: "|"))") }
            case "--snapshot": snapshot = next()
            case "--view": view = next()
            case "--day": night = false
            case "--night": night = true
            case "--select": select = next()
            case "--press": press = next()
            case "--exit-after": exitAfter = next().flatMap(Double.init)
            case "--open": open = true
            default: Args.fail("모르는 인자: \(a[i])")
            }
            i += 1
        }
        // 실제 자료에서 버튼을 누르면 phase.sh가 실행될 수 있다.
        if press != nil && demo == nil { Args.fail("--press는 --demo와 함께만 쓸 수 있습니다") }
    }

    static func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(2) }
}

/// 메모리 사용량(MB). phys_footprint와 resident size.
func memoryLine() -> String {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    guard kr == KERN_SUCCESS else { return "memory: 읽기 실패 \(kr)" }
    return String(format: "memory: phys_footprint %.1f MB, resident %.1f MB", Double(info.phys_footprint) / 1_048_576, Double(info.resident_size) / 1_048_576)
}

/// 패널의 시작 상태를 인자대로 맞춘다.
func configure(_ p: PanelView, _ args: Args, _ store: Store) {
    p.world = store.world; p.demo = store.demo != nil; p.hcMissing = store.hcMissing; p.hcDown = store.hcDown; p.loaded = store.loaded
    p.fixedNight = args.night
    let wantOffice = args.view == "office" || (args.view == "list" && (store.demo?.isOffice ?? true)) || (args.view == nil && store.demo?.isOffice == true)
    if wantOffice, !p.world.projects.isEmpty {
        // 실제 자료면 지금 폴더의 저장소, 없으면 첫 층.
        let here = ProjectGrouping.gitRoot(from: FileManager.default.currentDirectoryPath)
        p.officeRoot = (p.world.projects.first { $0.root == here } ?? p.world.projects[0]).root
        p.go(.office)
    }
    if args.view == "list" { p.go(.list) }
    if args.view == "building" { p.go(.building) }
    p.reload()
}

func snapshot(_ args: Args, to path: String) {
    _ = NSApplication.shared
    Fonts.register()
    let store = Store(demo: args.demo, saveFloors: false)
    let here = ProjectGrouping.gitRoot(from: FileManager.default.currentDirectoryPath)
    store.loadOnce(focus: args.view == "office" || args.view == "list" ? here : nil)
    let p = PanelView(frame: CGRect(x: 0, y: 0, width: 480, height: 300))
    p.noSend = true  // 화면 찍기는 무엇도 보내지 않는다
    p.appearance = NSAppearance(named: .aqua)
    configure(p, args, store)
    if let s = args.select, case .office = p.mode {
        let hits = p.scene.overlay.subviews.compactMap { $0 as? HitButton }
        // 상자는 진행 중인 것(대기·완료 선반이 아닌 것)을 먼저 고른다.
        let boxes = hits.filter { if case .box = $0.kind { return true } else { return false } }
        let busy = boxes.first { b in !["대기 단계", "완료 단계"].contains { (b.accessibilityLabel() ?? "").contains($0) } }
        // `actor:2`는 둘째 캐릭터를 고른다.
        let actors = hits.filter { if case .actor = $0.kind { return true } else { return false } }
        let nth = Int(s.split(separator: ":").dropFirst().first ?? "") ?? 1
        let pick = s == "box" ? busy ?? boxes.first : actors.indices.contains(nth - 1) ? actors[nth - 1] : nil
        pick?.onPress()
    }
    // 입력칸이나 중단 확인 같은 지반 상태를 찍는다. 예시 자료면 보내지 않는다.
    if let b = args.press { p.ground.press(b) }
    p.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = p.bounds.size
    p.cacheDisplay(in: p.bounds, to: rep)
    // 패널의 둥근 모서리(10px)를 남기고 바깥을 비운다.
    let ctx = CGContext(data: nil, width: 960, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 960, height: 600), cornerWidth: 20, cornerHeight: 20, transform: nil)); ctx.clip()
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: 960, height: 600))
    let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    do { try out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)); print(path) }
    catch { Args.fail("저장 실패: \(error)") }
}

let args = Args(CommandLine.arguments)
if let path = args.snapshot { snapshot(args, to: path); exit(0) }

// 인스턴스는 하나. 잠금 파일을 잡지 못하면 이미 떠 있는 것이다.
try? FileManager.default.createDirectory(at: Store.supportDir, withIntermediateDirectories: true)
let lockFD = open(Store.supportDir.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 { Args.fail("mmcode-monitor가 이미 실행 중입니다") }

let app = NSApplication.shared
let controller = AppController(args)
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
