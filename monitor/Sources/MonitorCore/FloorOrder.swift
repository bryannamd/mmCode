/// 층 순서를 고정한다. 한 번 정한 순서는 프로젝트가 사라졌다 다시 나타나도 바뀌지 않는다.
public enum FloorOrder {
    /// 층이 될 프로젝트만 고른다. 에이전트가 있었던 적도 없고 기록도 없는 프로젝트(셸만 있는 곳)는 뺀다.
    /// 이미 아는 층은 에이전트가 떠나도 남는다(어두운 층).
    public static func admit(known: [String], projects: [Project]) -> [Project] {
        let k = Set(known)
        return projects.filter { k.contains($0.root) || !$0.agents.isEmpty || $0.hasEvents }
    }

    /// - Parameters:
    ///   - known: 지금까지 아는 순서(프로젝트 루트).
    ///   - current: 지금 보이는 프로젝트.
    /// - Returns: `known`은 새 프로젝트를 끝에 붙인 전체 순서(저장해 두었다가 다음에 넘긴다). `visible`은 지금 보이는 것만 그 순서로 나열한 목록.
    public static func merge(known: [String], current: [String]) -> (known: [String], visible: [String]) {
        var all: [String] = []
        var seen = Set<String>()
        for id in known + current where seen.insert(id).inserted { all.append(id) }
        let now = Set(current)
        return (all, all.filter { now.contains($0) })
    }
}
