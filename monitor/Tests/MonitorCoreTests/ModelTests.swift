import Foundation
import Testing
@testable import MonitorCore

@Test func modelHaltClass() {
    #expect(Halt(reason: "decision", unit: nil, ts: Date(timeIntervalSince1970: 0)).kind == .decision)
    #expect(Halt(reason: "stop-after", unit: nil, ts: Date(timeIntervalSince1970: 0)).kind == .userStop)
    #expect(Halt(reason: "blocked:U3", unit: "U3", ts: Date(timeIntervalSince1970: 0)).kind == .unitBlocked)
    #expect(Halt(reason: "limit:iterations", unit: nil, ts: Date(timeIntervalSince1970: 0)).kind == .environment)
}
