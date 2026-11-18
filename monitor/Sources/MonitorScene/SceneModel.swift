import CoreGraphics
import MonitorCore

// 그리기와 글자 층이 쓰는 값. 시안의 내부 상태(actors, units, lamp, floors)를 본뜬다.
// 좌표는 모두 논리 좌표(240×108)다. 화면에서는 2배로 확대한다.

/// 털 무늬 하나가 캐릭터 그림 하나다(시안 COAT).
public enum Coat: String, Sendable, CaseIterable {
    case tuxedo, calico, tabby, white, catGray, beagle, dogSpot, frog, frogSpot
}

/// 동작은 상태다. 시안의 state 값 중 이동(go)과 확인(think)은 이번 범위가 아니다.
public enum Pose: String, Sendable {
    /// 타자. 책상 모니터가 켜진다.
    case work
    /// 졸기. 소파에 앉는다.
    case sleep
    /// 손들기와 물음표. 결정 대기나 입력 대기.
    case ask
    /// 손들기와 느낌표. hc 오류.
    case error
    case done
    /// 서 있기(시안의 idle).
    case wait
    /// 멈춤 표시. 사용자 정지.
    case stopped
}

/// 캐릭터가 서는 자리(시안 SPOT).
public enum Spot: Equatable, Sendable {
    case desk(Int), test, ui, bell, sofa(Int)

    /// 발 가운데 좌표.
    public var point: (x: Int, y: Int) {
        switch self {
        case .desk(let i): return (OfficeLayout.desks[i], 84)
        case .test: return (167, 84)
        case .ui: return (197, 84)
        case .bell: return (122, 100)
        case .sofa(let i): return (i == 0 ? 21 : 33, 98)
        }
    }
}

/// 시안에서 읽은 자리와 수용 인원.
public enum OfficeLayout {
    public static let desks = [80, 108, 136]
    public static let bellX = 130
    public static let sofaSeats = 2
    /// 선반 한 칸에 상자 2개, 2단.
    public static let shelfSlots = 4
    /// 단계 이름표(글자, 가운데 x).
    public static let rail: [(String, Int)] = [("대기", 44), ("구현", 108), ("검증", 165), ("검수", 197), ("완료", 223)]
}

public enum BuildingLayout {
    public static let floorY = 10, floorH = 23
    /// 건물 몸통(y 8~102)에 들어가는 층 수.
    public static let visibleFloors = 4
    /// 층 하나에 그리는 캐릭터 수(x 104부터 22 간격, 216 안).
    public static let agentsPerFloor = 5
    /// 층 이름표 아래 진행 칸 수(이름표 너비 62 안).
    public static let cellsPerFloor = 10
}

public struct SceneActor: Equatable, Sendable, Identifiable {
    /// hc 터미널 주소.
    public var id: String
    public var name: String
    public var harness: Harness
    public var model: String?
    public var effort: String?
    public var status: AgentStatus
    public var coat: Coat
    public var pose: Pose
    public var spot: Spot
    /// 든 상자. 걷는 중간 동작이 이번 범위가 아니므로 SceneBuilder는 채우지 않는다.
    public var carry: SceneBox?
    /// 목록과 지반에 쓰는 상태 글자.
    public var stateText: String
    public var statusText: String?
}

public enum BoxPlace: Equatable, Sendable {
    case backlog(slot: Int), done(slot: Int), desk(Int), test, ui

    /// 상자 왼쪽 위(시안 boxPos).
    public var point: (x: Int, y: Int) {
        switch self {
        case .backlog(let s): return (32 + (s % 2) * 12, 47 + (s / 2) * 16)
        case .done(let s): return (212 + (s % 2) * 12, 63 - (s / 2) * 16)
        case .desk(let i): return (OfficeLayout.desks[i] + 1, 51)
        case .test: return (157, 51)
        case .ui: return (192, 51)
        }
    }
}

public struct SceneBox: Equatable, Sendable, Identifiable {
    public var id: String
    public var number: Int?
    public var title: String?
    public var phase: Phase
    public var place: BoxPlace
    public var blocked: Bool
}

/// 시험대의 3색 신호등.
public enum Lamp: Sendable { case off, run, ok, fail }

/// 건물 층 옆 분홍 등의 모양.
public enum FloorAlert: Sendable { case ask, error }

public struct OfficeScene: Equatable, Sendable {
    public var night: Bool
    public var actors: [SceneActor]
    public var boxes: [SceneBox]
    public var lamp: Lamp
    /// 열린 결정이 있으면 벨이 분홍이 된다.
    public var bell: Bool
    /// 문 옆 정지 표지판.
    public var stopSign: Bool
    /// 환경·한도 멈춤. 문 위에 느낌표를 단다.
    public var officeError: Bool
    /// 자리가 모자라 그리지 못한 캐릭터와 상자 수. 목록에는 모두 나온다.
    public var hiddenActors: Int
    public var hiddenBoxes: Int
    public var labels: [WallLabel]
    public var bubbles: [Bubble]
    public var hits: [HitTarget]
}

public struct FloorAgent: Equatable, Sendable { public var coat: Coat; public var pose: Pose }

public struct BuildingFloor: Equatable, Sendable {
    /// `World.projects`의 위치.
    public var index: Int
    public var name: String
    public var agents: [FloorAgent]
    public var done: Int
    public var total: Int
    public var alert: FloorAlert?
}

public struct BuildingScene: Equatable, Sendable {
    public var night: Bool
    /// 보이는 층만, 위에서 아래로.
    public var floors: [BuildingFloor]
    public var firstFloor: Int
    public var moreAbove: Bool
    public var moreBelow: Bool
    public var labels: [WallLabel]
    public var hits: [HitTarget]
}

/// 장면 위에 AppKit이 글자로 그리는 이름표.
public struct WallLabel: Equatable, Sendable {
    public enum Style: Sendable { case stage, floorName }
    public var text: String
    public var style: Style
    /// stage: 가운데 x와 위 y. floorName: 이름표 칸의 사각형.
    public var rect: CGRect
}

/// 말풍선 후보. 꼬리 끝(캐릭터 머리 위)이 기준이다. 어느 것을 언제 보일지는 AppKit이 정한다.
public struct Bubble: Equatable, Sendable {
    public var text: String
    public var actorID: String
    public var anchor: CGPoint
}

public struct HitTarget: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case actor(String), box(String), floor(Int) }
    public var kind: Kind
    public var rect: CGRect
    /// 화면 낭독기용 이름.
    public var label: String
}

// MARK: 지붕과 지반

public struct RoofModel: Equatable, Sendable {
    public struct Alert: Equatable, Sendable {
        public var floor: Int
        /// 넓을 때. 예: "모바일 앱 층 한도 초과".
        public var long: String
        /// 좁을 때. 예: "다른 층 1건".
        public var short: String
    }
    public var title: String
    /// 단위 진행 칸. true가 완료. 기록이 없으면 비어 있다.
    public var cells: [Bool]
    /// "완료 3/6" 또는 "4개 층".
    public var count: String?
    /// 다른 층의 알림. 건물 보기에서는 nil.
    public var alert: Alert?
    public var isDemo: Bool
}

public enum GroundIcon: Equatable, Sendable {
    case face(Coat, Pose), bell, stop, box(number: Int?, done: Bool), building
}

public enum GroundAction: Equatable, Sendable {
    case answer(decision: String, text: String)
    /// 답을 직접 적는다.
    case reply(decision: String)
    case message(terminal: String)
    /// 객관식 질문의 선택지 번호를 `hc keys`로 누른다.
    case choose(terminal: String, number: Int)
    case stopAfter, interrupt, resume
    case enterFloor(Int)
}

public struct GroundButton: Equatable, Sendable {
    public var label: String
    public var primary: Bool
    public var disabled: Bool
    public var action: GroundAction

    public init(_ label: String, _ action: GroundAction, primary: Bool = false, disabled: Bool = false) {
        self.label = label; self.action = action; self.primary = primary; self.disabled = disabled
    }
}

public struct GroundModel: Equatable, Sendable {
    /// 당신 차례면 분홍 지반.
    public var turn: Bool
    /// 이 문장이 말하는 층(`World.projects`의 위치). 버튼의 대상 프로젝트다.
    public var floor: Int?
    public var icon: GroundIcon
    public var title: String
    public var pill: String?
    public var detail: String
    public var buttons: [GroundButton]
}

// MARK: 목록 보기

public struct ListTag: Equatable, Sendable {
    public enum Style: Sendable { case plain, turn, halt }
    public var text: String
    public var style: Style
}

public struct ListRow: Equatable, Sendable {
    public var face: FloorAgent?
    public var title: String
    public var subtitle: String?
    public var tags: [ListTag]
    public var meta: String?
}

public struct ListSection: Equatable, Sendable {
    public var title: String
    public var wide: Bool
    public var rows: [ListRow]
}

public struct ListModel: Equatable, Sendable { public var sections: [ListSection] }

/// 한 화면에 필요한 모든 값.
public struct OfficeView: Equatable, Sendable {
    public var scene: OfficeScene
    public var roof: RoofModel
    public var ground: GroundModel
    public var list: ListModel
}

public struct BuildingView: Equatable, Sendable {
    public var scene: BuildingScene
    public var roof: RoofModel
    public var ground: GroundModel
    public var list: ListModel
}
