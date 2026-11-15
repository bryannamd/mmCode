import Foundation

/// 터미널을 git 저장소 루트로 묶어 프로젝트(층)를 만든다.
public final class ProjectGrouping {
    private let findRoot: (String) -> String
    private let readLog: (URL) -> EventLog.Result
    private var cache: [String: (size: UInt64, mtime: Date, plans: [PlanState])] = [:]

    /// 시험에서 `findRoot`와 `readLog`를 바꿔 끼운다.
    public init(findRoot: @escaping (String) -> String = ProjectGrouping.gitRoot(from:),
                readLog: @escaping (URL) -> EventLog.Result = EventLog.read(url:)) {
        self.findRoot = findRoot
        self.readLog = readLog
    }

    /// 프로젝트는 처음 본 터미널 순서로 나온다. 층 순서 고정은 `FloorOrder`가 맡는다.
    public func group(_ terminals: [Terminal]) -> [Project] {
        var order: [String] = []
        var byRoot: [String: [Terminal]] = [:]
        // 작업 폴더가 없는 터미널은 묶을 곳이 없다. 빈 경로는 앱의 작업 폴더로 읽히므로 뺀다.
        for t in terminals where !t.cwd.isEmpty {
            let root = findRoot(t.cwd)
            if byRoot[root] == nil { order.append(root) }
            byRoot[root, default: []].append(t)
        }
        return order.map { root in
            Project(root: root, name: URL(fileURLWithPath: root).lastPathComponent, terminals: byRoot[root] ?? [], plans: plans(root: root))
        }
    }

    /// `<루트>/.mmcode/events.jsonl`의 계획들. 파일이 없으면 빈 목록.
    /// ponytail: 크기와 수정 시각이 바뀌면 전체를 다시 읽는다. 파일이 커져 느려지면 읽은 위치부터 증분 읽기로 바꾼다.
    public func plans(root: String) -> [PlanState] {
        let path = root + "/.mmcode/events.jsonl"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let mtime = attrs[.modificationDate] as? Date else {
            cache[root] = nil
            return []
        }
        if let c = cache[root], c.size == size, c.mtime == mtime { return c.plans }
        let plans = readLog(URL(fileURLWithPath: path)).plans
        cache[root] = (size, mtime, plans)
        return plans
    }

    /// 작업 폴더에서 위로 올라가며 `.git`(폴더 또는 파일)을 찾는다. git을 실행하지 않는다.
    /// 못 찾으면 작업 폴더가 루트다.
    public static func gitRoot(from cwd: String) -> String {
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir.path }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return URL(fileURLWithPath: cwd).path }
            dir = parent
        }
    }
}
