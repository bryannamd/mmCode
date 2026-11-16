import Foundation

// 모니터의 자료 모델. 자료 층과 장면 층이 함께 쓰는 계약이다.
// 낱말과 기계 값은 docs/plans/orchestration-plan.md 3절과 4.1절을 그대로 따른다.

// MARK: 하네스와 단계

/// 에이전트를 실행하는 도구. `hc ls`의 `agent` 값과 이벤트의 `actor.harness` 값이다.
public enum Harness: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex
    case agy
    /// 셸(zsh)처럼 에이전트가 아닌 것. 캐릭터로 그리지 않는다.
    case other

    public init(raw: String) { self = Harness(rawValue: raw) ?? .other }

    public var isAgent: Bool { self != .other }
}

/// 단위의 단계(3.2절). 장소와 1:1이다.
public enum Phase: String, Codable, Sendable, CaseIterable {
    case queued, build, verify, review, done

    /// 화면에 쓰는 이름.
    public var label: String {
        switch self {
        case .queued: return "대기"
        case .build: return "구현"
        case .verify: return "검증"
        case .review: return "검수"
        case .done: return "완료"
        }
    }
}

// MARK: 멈춤

/// 멈춤의 표시 분류(3.3절).
public enum HaltClass: String, Sendable, CaseIterable {
    case decision, userStop, unitBlocked, environment

    public var label: String {
        switch self {
        case .decision: return "결정 대기"
        case .userStop: return "사용자 정지"
        case .unitBlocked: return "단위 막힘"
        case .environment: return "환경·한도"
        }
    }
}

/// 풀리지 않은 멈춤 하나. `unit.halt`에서 생기고 `unit.resume`에서 없어진다.
public struct Halt: Equatable, Sendable {
    /// `data.reason`의 기계 값. 예: `decision`, `stop-after`, `interrupt`, `blocked:U3`, `limit:iterations`.
    public var reason: String
    /// 이벤트의 `unit`. 계획 전체의 멈춤이면 nil.
    public var unit: String?
    public var ts: Date
    /// 이 멈춤을 건 결정 요청(`data.decision`)과 지시(`data.directive`)의 ID.
    public var decision: String?
    public var directive: String?

    public init(reason: String, unit: String?, ts: Date, decision: String? = nil, directive: String? = nil) {
        self.reason = reason
        self.unit = unit
        self.ts = ts
        self.decision = decision
        self.directive = directive
    }

    public var kind: HaltClass {
        if reason == "decision" { return .decision }
        if reason == "stop-after" || reason == "interrupt" { return .userStop }
        if reason.hasPrefix("blocked") { return .unitBlocked }
        return .environment
    }

    /// `rotate`(정상 교체)와 `done`(완료)은 멈춤이 아니다. 이 값으로는 Halt를 만들지 않는다.
    public static func isHalt(reason: String) -> Bool { reason != "rotate" && reason != "done" }
}

// MARK: 증거

/// 증거의 종류(3.4절). `check.result`의 `data.kind` 값이다.
public enum EvidenceKind: String, Codable, Sendable, CaseIterable {
    case cmd, manual
    case failFirst = "fail-first"
    case review, mutation
    case crossReview = "cross-review"
    case coverage
    case uiReview = "ui-review"

    public var label: String {
        switch self {
        case .cmd: return "검사 명령"
        case .manual: return "실제 확인"
        case .failFirst: return "실패 먼저"
        case .review: return "독립 검수"
        case .mutation: return "변형 점검"
        case .crossReview: return "교차 검토"
        case .coverage: return "커버리지"
        case .uiReview: return "UI 검수"
        }
    }
}

/// `check.result` 이벤트 하나.
public struct Evidence: Equatable, Sendable {
    public var kind: EvidenceKind
    public var pass: Bool
    public var command: String?
    public var exit: Int?
    public var reason: String?
    /// 증거 파일 경로.
    public var path: String?
    public var ts: Date

    public init(kind: EvidenceKind, pass: Bool, command: String? = nil, exit: Int? = nil, reason: String? = nil, path: String? = nil, ts: Date) {
        self.kind = kind
        self.pass = pass
        self.command = command
        self.exit = exit
        self.reason = reason
        self.path = path
        self.ts = ts
    }
}

// MARK: 행위자

/// 이벤트를 쓴 쪽. 빈 키는 기록에서 빠지므로 모두 선택 값이다.
public struct Actor: Equatable, Sendable {
    /// `hc` 터미널 주소. 예: `t3d`.
    public var terminal: String?
    public var harness: Harness?
    /// 하네스가 보고한 ID 그대로. 예: `claude-fable-5-2`.
    public var model: String?
    public var effort: String?

    public init(terminal: String? = nil, harness: Harness? = nil, model: String? = nil, effort: String? = nil) {
        self.terminal = terminal
        self.harness = harness
        self.model = model
        self.effort = effort
    }
}

// MARK: 단위, 결정, 지시

/// 단위 하나의 현재 상태. ID는 `U<번호>` 또는 `U<번호>-fix<회차>`다.
public struct UnitState: Equatable, Sendable, Identifiable {
    public var id: String
    /// 계획 파일의 단위 이름. 기록에는 없으므로 모르면 nil.
    public var title: String?
    public var phase: Phase
    /// 이 단위에 걸린 풀리지 않은 멈춤.
    public var halt: Halt?
    /// 받은 순서대로의 증거 전체. 종류별 최신 값은 `latest(_:)`로 읽는다.
    public var evidence: [Evidence]
    /// `unit.commit`의 해시 또는 `없음(변경 없음)`.
    public var commit: String?
    /// 마지막 `unit.phase`를 쓴 쪽. 상자를 든 담당자를 정할 때 쓴다.
    public var owner: Actor?
    /// 마지막으로 되돌아간 사유(`unit.phase`의 `data.reason`).
    public var backReason: String?
    public var updated: Date?

    public init(id: String, title: String? = nil, phase: Phase = .queued, halt: Halt? = nil, evidence: [Evidence] = [], commit: String? = nil, owner: Actor? = nil, backReason: String? = nil, updated: Date? = nil) {
        self.id = id
        self.title = title
        self.phase = phase
        self.halt = halt
        self.evidence = evidence
        self.commit = commit
        self.owner = owner
        self.backReason = backReason
        self.updated = updated
    }

    /// 상자에 적는 번호. `U7-fix1`이면 7.
    public var number: Int? {
        let digits = id.dropFirst().prefix { $0.isNumber }
        return Int(digits)
    }

    public func latest(_ kind: EvidenceKind) -> Evidence? { evidence.last { $0.kind == kind } }

    public var latestEvidence: Evidence? { evidence.last }
}

/// 결정 요청 하나. 답이 없으면 결정 대기열에 있다.
public struct Decision: Equatable, Sendable, Identifiable {
    public var id: String
    public var question: String
    public var recommendation: String?
    public var impact: String?
    /// 고를 수 있는 답. 없으면 비어 있다.
    public var options: [String]
    /// 막힌 단위의 ID.
    public var blocks: [String]
    /// 그동안 가능한 작업.
    public var meanwhile: String?
    public var asker: Actor?
    public var ts: Date
    /// 답. nil이면 아직 열려 있다.
    public var answer: String?

    public init(id: String, question: String, recommendation: String? = nil, impact: String? = nil, options: [String] = [], blocks: [String] = [], meanwhile: String? = nil, asker: Actor? = nil, ts: Date, answer: String? = nil) {
        self.id = id
        self.question = question
        self.recommendation = recommendation
        self.impact = impact
        self.options = options
        self.blocks = blocks
        self.meanwhile = meanwhile
        self.asker = asker
        self.ts = ts
        self.answer = answer
    }

    public var isOpen: Bool { answer == nil }
}

/// 지시의 종류(3.3절).
public enum DirectiveKind: String, Codable, Sendable, CaseIterable {
    case message
    case stopAfter = "stop-after"
    case interrupt, reorder, resume

    public var label: String {
        switch self {
        case .message: return "메시지"
        case .stopAfter: return "단위 후 정지"
        case .interrupt: return "즉시 중단"
        case .reorder: return "순서 변경"
        case .resume: return "계속"
        }
    }
}

public enum DirectiveStatus: String, Sendable {
    case received, applied, rejected

    public var label: String {
        switch self {
        case .received: return "접수"
        case .applied: return "적용됨"
        case .rejected: return "거부됨"
        }
    }
}

public struct Directive: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: DirectiveKind
    public var text: String?
    public var status: DirectiveStatus
    /// 거부한 사유.
    public var reason: String?
    /// 받을 터미널 주소(메시지).
    public var terminal: String?
    /// 계속(resume) 지시가 `closes`로 닫았다.
    public var closed: Bool
    public var ts: Date

    public init(id: String, kind: DirectiveKind, text: String? = nil, status: DirectiveStatus = .received, reason: String? = nil, terminal: String? = nil, closed: Bool = false, ts: Date) {
        self.id = id
        self.kind = kind
        self.text = text
        self.status = status
        self.reason = reason
        self.terminal = terminal
        self.closed = closed
        self.ts = ts
    }

    /// 정지·중단은 적용된 뒤에도 계속 지시가 닫을 때까지 열려 있다. 계속은 접수가 곧 적용이라 열리지 않는다.
    /// 메시지·순서 변경은 적용이나 거부로 닫힌다.
    public var isOpen: Bool {
        switch kind {
        case .stopAfter, .interrupt: return !closed
        case .resume: return false
        case .message, .reorder: return status == .received
        }
    }

    /// 열린 정지·중단 지시인가.
    public var isOpenStop: Bool { (kind == .stopAfter || kind == .interrupt) && isOpen }
}

// MARK: 계획, 터미널, 프로젝트

/// 같은 `plan` 값의 이벤트를 모아 계산한 상태.
public struct PlanState: Equatable, Sendable {
    public var plan: String
    /// 단위 번호 순서. 이벤트가 없는 단위는 `queued`다.
    public var units: [UnitState]
    /// 단위에 걸리지 않은 멈춤(계획 전체).
    public var halts: [Halt]
    /// 받은 순서대로의 결정 요청 전체. 열린 것은 `openDecisions`로 읽는다.
    public var decisions: [Decision]
    public var directives: [Directive]
    /// 터미널 주소별로 가장 최근에 본 행위자 정보. 모델과 effort를 여기서 읽는다.
    public var actors: [String: Actor]
    public var updated: Date?

    public init(plan: String, units: [UnitState] = [], halts: [Halt] = [], decisions: [Decision] = [], directives: [Directive] = [], actors: [String: Actor] = [:], updated: Date? = nil) {
        self.plan = plan
        self.units = units
        self.halts = halts
        self.decisions = decisions
        self.directives = directives
        self.actors = actors
        self.updated = updated
    }

    public var openDecisions: [Decision] { decisions.filter { $0.isOpen } }

    /// 열린 정지·중단 지시. 접수만 된 것과 적용된 것을 `status`로 나눈다.
    public var openStops: [Directive] { directives.filter(\.isOpenStop) }

    /// 단위에 걸린 것과 계획 전체의 것을 합친 풀리지 않은 멈춤.
    public var allHalts: [Halt] { halts + units.compactMap { $0.halt } }

    public var doneCount: Int { units.filter { $0.phase == .done }.count }
}

/// `hc`가 보고하는 에이전트의 상태(`status`).
public enum AgentStatus: String, Sendable {
    case working, idle, done, blocked, error, unknown

    public init(raw: String?) { self = raw.flatMap(AgentStatus.init(rawValue:)) ?? .unknown }
}

/// `hc ls`의 터미널 하나.
public struct Terminal: Equatable, Sendable, Identifiable {
    /// 주소. 예: `t3d`.
    public var address: String
    public var harness: Harness
    /// `agent` 원문. 예: `zsh`.
    public var agentRaw: String
    public var cwd: String
    /// `live` 등.
    public var state: String
    public var status: AgentStatus
    public var turn: Int
    /// "스페이스 / 탭".
    public var location: String
    /// `hc get`의 상태 문구. 읽지 않았으면 nil.
    public var statusText: String?

    public var id: String { address }

    public init(address: String, harness: Harness, agentRaw: String, cwd: String, state: String = "live", status: AgentStatus = .unknown, turn: Int = 0, location: String = "", statusText: String? = nil) {
        self.address = address
        self.harness = harness
        self.agentRaw = agentRaw
        self.cwd = cwd
        self.state = state
        self.status = status
        self.turn = turn
        self.location = location
        self.statusText = statusText
    }

    /// 탭 이름. `location`의 " / " 뒤쪽.
    public var tabName: String {
        guard let r = location.range(of: " / ") else { return location }
        return String(location[r.upperBound...])
    }
}

/// 프로젝트 하나. 건물의 층 하나다. git 저장소 루트로 묶는다.
public struct Project: Equatable, Sendable, Identifiable {
    /// git 저장소 루트의 절대 경로. git 저장소가 아니면 작업 폴더.
    public var root: String
    /// 루트의 마지막 경로 요소.
    public var name: String
    public var terminals: [Terminal]
    /// `.mmcode/events.jsonl`의 계획별 상태. 파일이 없으면 비어 있다.
    public var plans: [PlanState]

    public var id: String { root }

    public init(root: String, name: String, terminals: [Terminal] = [], plans: [PlanState] = []) {
        self.root = root
        self.name = name
        self.terminals = terminals
        self.plans = plans
    }

    /// 캐릭터로 그릴 터미널.
    public var agents: [Terminal] { terminals.filter { $0.harness.isAgent } }

    /// 화면에 보여 줄 계획. 가장 최근에 이벤트가 있던 계획이다.
    /// 폴더에서 쓴 기록(plan `-`)은 EventLog가 다른 계획에 합치므로 다른 계획이 있으면 여기에 없다.
    public var activePlan: PlanState? {
        plans.max { ($0.updated ?? .distantPast) < ($1.updated ?? .distantPast) }
    }

    public var hasEvents: Bool { !plans.isEmpty }

    /// 모든 계획의 열린 결정. 계획과 상관없이 열린 결정은 모두 사용자 차례다(phase.sh show와 같다).
    /// 폴더 결정은 계획마다 합쳐져 있으므로 ID로 중복을 없앤다.
    public var openDecisions: [Decision] {
        var seen = Set<String>()
        return plans.flatMap(\.openDecisions).sorted { $0.ts < $1.ts }.filter { seen.insert($0.id).inserted }
    }

    /// 모든 계획의 결정 멈춤과 그 계획 값.
    public var decisionHalts: [(plan: String, halt: Halt)] {
        plans.flatMap { pl in pl.allHalts.filter { $0.kind == .decision }.map { (pl.plan, $0) } }
    }
}

/// 모든 프로젝트. 순서는 층의 순서다. 한 번 정한 순서는 바꾸지 않는다.
public struct World: Equatable, Sendable {
    public var projects: [Project]

    public init(projects: [Project] = []) { self.projects = projects }
}
