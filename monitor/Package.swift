// swift-tools-version: 6.0
import PackageDescription

// 모니터 앱. 계획: docs/plans/monitor-plan.md, 디자인 기준: DESIGN.md
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "MmcodeMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // 자료 층: 기록(events.jsonl)과 hc 출력을 읽어 현재 상태를 계산한다. AppKit을 쓰지 않는다.
        .target(name: "MonitorCore", swiftSettings: v5),
        // 장면 층: 상태를 장면으로 바꾸고 픽셀로 그린다. CoreGraphics만 쓴다.
        .target(name: "MonitorScene", dependencies: ["MonitorCore"], resources: [.process("Resources")], swiftSettings: v5),
        // 장면을 PNG로 저장하는 확인 도구.
        .executableTarget(name: "scene-snap", dependencies: ["MonitorCore", "MonitorScene"], swiftSettings: v5),
        // 메뉴 막대 앱.
        .executableTarget(name: "mmcode-monitor", dependencies: ["MonitorCore", "MonitorScene"], swiftSettings: v5),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"], resources: [.copy("Fixtures")], swiftSettings: v5),
        .testTarget(name: "MonitorSceneTests", dependencies: ["MonitorCore", "MonitorScene"], swiftSettings: v5),
    ]
)
