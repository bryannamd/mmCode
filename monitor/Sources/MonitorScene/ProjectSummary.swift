import Foundation
import MonitorCore

/// 프로젝트 행과 전체 개요가 같은 상태 판정을 사용한다.
public struct ProjectSummary: Equatable {
    public enum Activity: Int { case attention, working, paused, waiting, complete, unknown }
    public let root: String
    public let name: String
    public let priority: Int
    public let activity: Activity
    public let state: String
    public let detail: String
    public let requester: String?
    public let face: FloorAgent?
    public let working: Int
    public let agents: Int
}

extension SceneBuilder {
    public static func projectSummary(_ project: Project) -> ProjectSummary {
        let people = actors(project)
        let running = people.filter { $0.pose == .work }
        let plan = project.activePlan
        let urgent = urgent(project)
        let activity: ProjectSummary.Activity
        let state: String
        let detail: String
        var requester: String?
        var representative = running.first ?? people.first
        if let urgent {
            activity = urgent.turn ? .attention : .paused
            state = urgent.label
            switch urgent {
            case .decision(let d):
                detail = d.question
                let sender = people.first { $0.id == d.asker?.terminal }
                representative = sender ?? representative
                requester = sender?.name
            case .input(let t):
                detail = inputDetail(t)
                requester = name(t)
                representative = people.first { $0.id == t.address } ?? representative
            case .unitBlocked(let unit, let halt):
                detail = "\(unit.id) · \(blockedDetail(unit, halt))"
            case .environment(let text, _, _): detail = text
            case .userStop(let halt): detail = stopDetail(halt)
            }
        } else {
            if !running.isEmpty { activity = .working; state = "작업 중" }
            else if let plan, !plan.units.isEmpty, plan.doneCount == plan.units.count { activity = .complete; state = "완료" }
            else if !people.isEmpty && people.allSatisfy({ $0.status == .done }) { activity = .complete; state = "완료" }
            else if people.contains(where: { $0.status == .unknown }) { activity = .unknown; state = "상태 미확인" }
            else { activity = .waiting; state = people.isEmpty ? "담당자 없음" : "대기 중" }
            let activeUnit = plan?.units.first { [.build, .verify, .review].contains($0.phase) }
            if let unit = activeUnit {
                detail = [unit.id, unit.title, unit.phase.label].compactMap { $0 }.joined(separator: " · ")
            } else if let text = representative?.statusText, !text.isEmpty {
                detail = text
            } else {
                let names = (running.isEmpty ? people : running).map(\.name)
                detail = names.isEmpty ? "연결된 에이전트가 없어요" : "담당 " + names.joined(separator: " · ")
            }
        }
        return ProjectSummary(root: project.root, name: project.name, priority: urgent.map(rank) ?? (10 + activity.rawValue), activity: activity, state: state, detail: detail,
                              requester: requester, face: representative.map { FloorAgent(coat: $0.coat, pose: $0.pose) }, working: running.count, agents: people.count)
    }
}
