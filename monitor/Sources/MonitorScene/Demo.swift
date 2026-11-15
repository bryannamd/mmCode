import Foundation
import MonitorCore

// 시안의 예시 시나리오를 Model.swift의 타입으로 만든다. 값은 모두 예시 데이터다.

public extension Project {
    /// 예시 프로젝트. 지붕에 "예시"를 표시한다.
    var isDemo: Bool { root.hasPrefix(Demo.rootPrefix) }
}

public enum Demo: String, CaseIterable, Sendable {
    case quiet, decision, blocked, stopped, building, otherFloorAlert

    public static let rootPrefix = "demo:"

    /// 사무실 보기의 시나리오인가. 아니면 건물 보기로 연다.
    public var isOffice: Bool { self != .building }

    public var world: World {
        let mm: Project
        switch self {
        case .quiet, .otherFloorAlert: mm = Demo.mmCode(.quiet)
        case .decision, .building: mm = Demo.mmCode(.decision)
        case .blocked: mm = Demo.mmCode(.blocked)
        case .stopped: mm = Demo.mmCode(.stopped)
        }
        return World(projects: [mm, Demo.web, Demo.mobile(trouble: self == .otherFloorAlert), Demo.docs])
    }

    // MARK: 재료

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    private static func term(_ addr: String, _ proj: String, _ tab: String, _ h: Harness, _ st: AgentStatus, _ text: String? = nil) -> Terminal {
        Terminal(address: addr, harness: h, agentRaw: h.rawValue, cwd: "/demo/" + proj, status: st, location: "\(proj) / \(tab)", statusText: text)
    }

    private static func project(_ name: String, _ terms: [Terminal], _ plan: PlanState) -> Project {
        Project(root: rootPrefix + name, name: name, terminals: terms, plans: [plan])
    }

    private static func actors(_ list: [(String, Harness, String, String)]) -> [String: Actor] {
        Dictionary(uniqueKeysWithValues: list.map { ($0.0, Actor(terminal: $0.0, harness: $0.1, model: $0.2, effort: $0.3)) })
    }

    /// 번호 순서의 단위. 앞의 done개는 완료다.
    private static func units(_ n: Int, done: Int) -> [UnitState] {
        (1...n).map { UnitState(id: "U\($0)", phase: $0 <= done ? .done : .queued, updated: at(Double($0))) }
    }

    private static func mmCode(_ s: Demo) -> Project {
        let main = Actor(terminal: "t1", harness: .claudeCode, model: "claude-fable-5-2", effort: "high")
        let worker = Actor(terminal: "t2", harness: .claudeCode, model: "claude-sonnet-5-5", effort: "low")
        let rev = Actor(terminal: "t3", harness: .codex, model: "gpt-5.5", effort: "high")
        func u(_ id: String, _ title: String, _ ph: Phase, _ ev: [Evidence] = [], owner: Actor? = nil, halt: Halt? = nil) -> UnitState {
            UnitState(id: id, title: title, phase: ph, halt: halt, evidence: ev, owner: owner, updated: at(Double(id.dropFirst())! * 10))
        }
        func ev(_ k: EvidenceKind, _ pass: Bool, _ r: String? = nil) -> Evidence { Evidence(kind: k, pass: pass, reason: r, ts: t0) }
        let u1 = u("U1", "hc 환경 전환", .done, [ev(.cmd, true, "9/9"), ev(.failFirst, true), ev(.mutation, true), ev(.review, true)], owner: rev)
        let u2 = u("U2", "이벤트 파일과 훅", .done, [ev(.cmd, true, "14/14"), ev(.failFirst, true), ev(.review, true), ev(.crossReview, true, "지적 0건"), ev(.coverage, true, "82%")], owner: rev)
        let u3Done = u("U3", "모니터 조회판", .done, [ev(.cmd, true, "12/12"), ev(.uiReview, true), ev(.review, true, "필수 수정 0, 개선 1")], owner: rev)
        let rest = [u("U4", "클릭 개입", .queued), u("U5", "완료 기준 연결", .queued), u("U6", "알림 연결", .queued)]
        var terms = [term("t1", "mmCode", "계획자", .claudeCode, .working, "Write U3 브리프"),
                     term("t2", "mmCode", "일꾼", .claudeCode, .working, "Edit status.sh"),
                     term("t3", "mmCode", "검수자", .codex, .idle)]
        var plan = PlanState(plan: "docs/plans/monitor-plan.md", actors: actors([("t1", .claudeCode, "claude-fable-5-2", "high"), ("t2", .claudeCode, "claude-sonnet-5-5", "low"), ("t3", .codex, "gpt-5.5", "high")]), updated: at(100))
        switch s {
        case .blocked:
            terms[1].status = .idle; terms[1].statusText = "검사 명령 실패 3/12"
            plan.units = [u1, u2, u("U3", "모니터 조회판", .verify, [ev(.cmd, false, "3/12")], owner: worker, halt: Halt(reason: "blocked:U3", unit: "U3", ts: at(90)))] + rest
        case .decision:
            terms.remove(at: 1); terms[0].status = .idle; terms[0].statusText = "정본을 옮길지 묻는 중"
            plan.units = [u1, u2, u3Done] + rest
            plan.decisions = [Decision(id: "D1", question: "정본을 이벤트 파일로 옮길까요?", recommendation: "옮긴다", blocks: ["U4", "U5"], asker: main, ts: at(95))]
        case .stopped:
            terms.remove(at: 1); terms[0].status = .idle; terms[0].statusText = nil
            plan.units = [u1, u2, u3Done] + rest
            plan.halts = [Halt(reason: "stop-after", unit: nil, ts: at(95))]
            plan.directives = [Directive(id: "C1", kind: .stopAfter, text: "이 단위를 마치면 멈춤", status: .applied, ts: at(80))]
        default:
            plan.units = [u1, u2, u("U3", "모니터 조회판", .build, owner: worker)] + rest
        }
        return project("mmCode", terms, plan)
    }

    private static var web: Project {
        var us = units(7, done: 4); us[4].phase = .build; us[4].owner = Actor(terminal: "w1")
        return project("웹 프런트",
                       [term("w1", "웹 프런트", "일꾼", .claudeCode, .working), term("w2", "웹 프런트", "계획자", .claudeCode, .working), term("w3", "웹 프런트", "검수자", .codex, .idle)],
                       PlanState(plan: "web", units: us, actors: actors([("w1", .claudeCode, "claude-sonnet-5-5", "low"), ("w2", .claudeCode, "claude-opus-5-5", "high"), ("w3", .codex, "gpt-5.5-mini", "low")]), updated: at(60)))
    }

    private static func mobile(trouble: Bool) -> Project {
        var plan = PlanState(plan: "mobile", units: units(3, done: 1), actors: actors([("m1", .claudeCode, "claude-haiku-5-5", "low")]), updated: at(50))
        if trouble { plan.halts = [Halt(reason: "limit:iterations", unit: nil, ts: at(70))] }
        return project("모바일 앱", [term("m1", "모바일 앱", "일꾼", .claudeCode, trouble ? .error : .working)], plan)
    }

    private static var docs: Project {
        project("문서 사이트", [term("d1", "문서 사이트", "계획자", .agy, .done), term("d2", "문서 사이트", "일꾼", .agy, .idle)],
                PlanState(plan: "docs", units: units(6, done: 6), actors: actors([("d1", .agy, "gemini-3-pro", "high"), ("d2", .agy, "gemini-3-flash", "low")]), updated: at(40)))
    }
}
