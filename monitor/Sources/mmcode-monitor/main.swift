import AppKit
import MonitorCore
import MonitorScene

// 메뉴 막대 앱. 사용법:
//   mmcode-monitor [--demo <이름>] [--open] [--exit-after <초>]
//   mmcode-monitor --snapshot <png> [--demo <이름>] [--view office|building|list|icon] [--day|--night] [--select actor[:번호]|box] [--press <지반 버튼 이름>]

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
    let wantOffice = (args.view == "office" || args.view == "office-map") || (args.view == "list" && (store.demo?.isOffice ?? true)) || (args.view == nil && store.demo?.isOffice == true)
    if wantOffice, !p.world.projects.isEmpty {
        // 실제 자료면 지금 폴더의 저장소, 없으면 첫 층.
        let here = ProjectGrouping.gitRoot(from: FileManager.default.currentDirectoryPath)
        p.officeRoot = (p.world.projects.first { $0.root == here } ?? p.world.projects[0]).root
        p.go(.office)
    }
    if args.view == "list" { p.go(.list) }
    if args.view == "building" || args.view == "building-map" { p.go(.building) }
    if args.view == "building-map" || args.view == "office-map" { p.roof.map.onPress() }
    p.reload()
}

func snapshot(_ args: Args, to path: String) {
    _ = NSApplication.shared
    Fonts.register()
    let store = Store(demo: args.demo, saveFloors: false)
    let here = ProjectGrouping.gitRoot(from: FileManager.default.currentDirectoryPath)
    store.loadOnce(focus: ["office", "office-map", "list"].contains(args.view ?? "") ? here : nil)
    if args.view == "icon" {
        let image = PostCat.state(store).image
        let icon = NSImageView(frame: CGRect(origin: .zero, size: image.size))
        icon.image = image
        icon.contentTintColor = args.night == true ? .white : .black
        saveSnapshot(icon, radius: 0, to: path)
        return
    }
    // 실제 창과 같은 크기를 레티나 2배 픽셀로 찍는다.
    let p = PanelView(frame: CGRect(origin: .zero, size: PanelView.size))
    p.noSend = true  // 화면 찍기는 무엇도 보내지 않는다
    p.appearance = NSAppearance(named: .aqua)
    configure(p, args, store)
    if let s = args.select, case .office = p.mode {
        if let i = p.officeIndex {
            let project = p.world.projects[i]
            let o = SceneBuilder.office(p.world, project: i, night: p.night)
            if s == "box", let box = o.scene.boxes.first(where: { [.build, .verify, .review].contains($0.phase) }) ?? o.scene.boxes.first {
                p.selectTarget(.box(box.id))
            } else {
                let actors = SceneBuilder.actors(project)
                let nth = Int(s.split(separator: ":").dropFirst().first ?? "") ?? 1
                if nth > 0, actors.indices.contains(nth - 1) { p.selectTarget(.actor(actors[nth - 1].id)) }
            }
        }
    }
    // 입력칸이나 중단 확인 같은 지반 상태를 찍는다. 예시 자료면 보내지 않는다.
    if let b = args.press { p.ground.press(b) }
    saveSnapshot(p, radius: AppController.radius, to: path)
}

func saveSnapshot(_ p: NSView, radius: CGFloat, to path: String) {
    p.layoutSubtreeIfNeeded()
    let W = Int(p.bounds.width * 2), H = Int(p.bounds.height * 2)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = p.bounds.size
    p.cacheDisplay(in: p.bounds, to: rep)
    // 패널의 둥근 모서리를 남기고 바깥을 비운다.
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: W, height: H), cornerWidth: radius * 2, cornerHeight: radius * 2, transform: nil)); ctx.clip()
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
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
