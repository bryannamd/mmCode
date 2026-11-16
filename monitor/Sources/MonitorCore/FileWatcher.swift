import Foundation

/// 파일 하나의 변경(쓰기, 늘어남, 이름 바뀜, 삭제)을 `DispatchSource`로 알린다. 폴링하지 않는다.
/// 파일이 없으면 있는 가장 가까운 상위 폴더를 보다가, 파일이 생기면 파일로 옮긴다.
public final class FileWatcher {
    private let path: String
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "mmcode.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private var running = false

    /// `onChange`는 이 객체의 내부 큐에서 불린다. UI를 건드리려면 메인으로 넘긴다.
    public init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit { source?.cancel() }

    public func start() { queue.sync { running = true; arm() } }

    /// `onChange` 안에서 부르지 않는다(같은 큐에서 기다리게 된다).
    public func stop() { queue.sync { running = false; source?.cancel(); source = nil } }

    private func arm() {
        source?.cancel()
        source = nil
        guard running else { return }
        var target = path
        var isFile = true
        while !FileManager.default.fileExists(atPath: target) {
            target = (target as NSString).deletingLastPathComponent
            isFile = false
            if target.isEmpty || target == "/" { break }
        }
        let fd = open(target, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: isFile ? [.write, .extend, .rename, .delete] : [.write, .rename, .delete], queue: queue)
        s.setEventHandler { [weak self, weak s] in
            guard let self, let s else { return }
            self.onChange()
            // 폴더를 보는 중이거나 파일이 바뀌어 사라졌으면 대상을 다시 고른다.
            if !isFile || !s.data.isDisjoint(with: [.rename, .delete]) { self.arm() }
        }
        s.setCancelHandler { close(fd) }
        source = s
        s.resume()
        // 대상을 고르는 사이에 파일이 생겼으면 생성 알림을 놓친다. 한 번 더 본다.
        if !isFile, FileManager.default.fileExists(atPath: path) { onChange(); arm() }
    }
}

/// 여러 층의 기록 파일(`<루트>/.mmcode/events.jsonl`)을 지켜본다. 다른 층의 멈춤도 바로 알린다.
/// 기록 폴더(`.mmcode`)가 없는 층은 보지 않는다. 그런 층까지 보면 프로젝트 폴더의 모든 파일 생성에 깨어난다.
public final class LogWatchers {
    private var watchers: [String: FileWatcher] = [:]
    private let onChange: () -> Void

    /// `onChange`는 감시자의 내부 큐에서 불린다.
    public init(onChange: @escaping () -> Void) { self.onChange = onChange }

    public var roots: Set<String> { Set(watchers.keys) }

    /// 지금 보이는 층에 맞춘다. 사라진 층은 그만 보고, 새 층은 보기 시작한다.
    public func sync(roots: [String]) {
        let want = Set(roots.filter { FileManager.default.fileExists(atPath: $0 + "/.mmcode") })
        for (r, w) in watchers where !want.contains(r) { w.stop(); watchers[r] = nil }
        for r in want where watchers[r] == nil {
            let w = FileWatcher(path: r + "/.mmcode/events.jsonl", onChange: onChange)
            watchers[r] = w
            w.start()
        }
    }

    public func stopAll() { sync(roots: []) }
}
