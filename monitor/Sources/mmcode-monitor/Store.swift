import Foundation
import MonitorCore
import MonitorScene

/// 자료를 한 곳에 모은다. 예시 자료면 고정값, 실제 자료면 `hc events`의 변화가 올 때만 다시 읽는다(폴링 없음).
/// 프로세스 실행과 파일 읽기는 `q`에서, 화면에 넘기는 일만 메인에서 한다.
final class Store {
    private(set) var world = World()
    private(set) var hcMissing = false
    /// `hc ls`가 실패했다(서버가 꺼져 있는 등). 다음에 성공하면 풀린다.
    private(set) var hcDown = false
    private(set) var loaded = false
    let demo: Demo?
    /// 메인 스레드에서 불린다.
    var onChange: () -> Void = {}

    private let q = DispatchQueue(label: "mmcode.store")
    private let grouping = ProjectGrouping()
    private let saveFloors: Bool
    private var known: [String] = []
    private var stream: HcClient.EventStream?
    private lazy var watchers = LogWatchers { [weak self] in self?.q.async { self?.schedule() } }
    private var focusRoot: String?
    private var pending = false, stopped = false

    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mmcode-monitor")
    private static var floorsFile: URL { supportDir.appendingPathComponent("floors.json") }

    init(demo: Demo?, saveFloors: Bool = true) {
        self.demo = demo; self.saveFloors = saveFloors
        if let demo { world = demo.world; loaded = true }
        else { known = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: Self.floorsFile))) ?? [] }
    }

    func start() { if demo == nil { q.async { self.launch() } } }

    /// 앱이 끝날 때 부른다. 이 객체가 띄운 스트림 프로세스만 끝낸다.
    func stop() { q.sync { stopped = true; stream?.stop(); stream = nil; watchers.stopAll() } }

    /// 화면 밖 캡처용. 지금 바로 한 번 읽는다.
    func loadOnce(focus: String?) {
        guard demo == nil else { return }
        q.sync { focusRoot = focus; if HcClient.locate() == nil { hcMissing = true } else { refresh(sync: true) } }
    }

    /// 사무실로 보는 프로젝트를 정한다. 상태 문구(`hc get`)는 이 프로젝트 것만 읽는다.
    func setFocus(_ root: String?) {
        guard demo == nil else { return }
        q.async { [self] in
            guard root != focusRoot else { return }
            focusRoot = root
            schedule()
        }
    }

    private func launch() {
        guard !stopped else { return }
        do {
            let s = try HcClient.EventStream()
            try s.start(onLine: { [weak self] line in
                guard HcClient.isChange(line: line) else { return }
                self?.q.async { self?.schedule() }
            }, onExit: { [weak self] in
                // hc 서버가 다시 시작되면 스트림이 끝난다. 5초 뒤에 다시 띄운다.
                self?.q.asyncAfter(deadline: .now() + 5) { self?.launch() }
            })
            stream = s
        } catch HcClient.HcError.notFound {
            DispatchQueue.main.async { self.hcMissing = true; self.onChange() }
        } catch {
            q.asyncAfter(deadline: .now() + 5) { self.launch() }
        }
    }

    /// 변화가 몰리면 0.3초 묶어서 한 번만 읽는다.
    private func schedule() {
        guard !pending, !stopped else { return }
        pending = true
        q.asyncAfter(deadline: .now() + 0.3) { self.pending = false; self.refresh(sync: false) }
    }

    private func refresh(sync: Bool) {
        guard let terms = try? HcClient.list() else {
            if sync { hcDown = true } else { DispatchQueue.main.async { self.hcDown = true; self.onChange() } }
            return
        }
        let projects = FloorOrder.admit(known: known, projects: grouping.group(terms))
        let m = FloorOrder.merge(known: known, current: projects.map(\.root))
        if m.known != known {
            known = m.known
            if saveFloors {
                try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
                try? JSONEncoder().encode(known).write(to: Self.floorsFile, options: .atomic)
            }
        }
        let byRoot = Dictionary(projects.map { ($0.root, $0) }, uniquingKeysWith: { a, _ in a })
        var ordered = m.visible.compactMap { byRoot[$0] }
        // 상태 문구(hc get)는 지금 사무실로 보는 프로젝트의 에이전트만 읽는다.
        if let f = focusRoot, let i = ordered.firstIndex(where: { $0.root == f }) {
            for k in ordered[i].terminals.indices where ordered[i].terminals[k].harness.isAgent {
                let t = ordered[i].terminals[k], s = HcClient.status(of: t.address)
                ordered[i].terminals[k].statusText = s.text
                // 객관식 질문이 떠 있으면 화면을 읽어 질문과 선택지를 뽑는다. blocked인 터미널만 화면을 읽는다.
                if t.status == .blocked, s.kind == "question", let screen = try? HcClient.read(address: t.address, lines: 0) {
                    ordered[i].terminals[k].question = QuestionScreen.parse(screen)
                }
            }
        }
        // 화면 밖 캡처(sync)는 한 번 읽고 끝나므로 지켜보지 않는다.
        if !sync, !stopped { watchers.sync(roots: ordered.map(\.root)) }
        let w = World(projects: ordered)
        let apply = { self.world = w; self.loaded = true; self.hcMissing = false; self.hcDown = false; self.onChange() }
        if sync { world = w; loaded = true; hcDown = false } else { DispatchQueue.main.async(execute: apply) }
    }
}
