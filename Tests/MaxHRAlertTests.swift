import XCTest
@testable import HRMRead

final class MaxHRAlertTests: XCTestCase {
    func testSustainedLimitLoopsUntilStrictlyBelow() {
        var gate = MaxHRAlertGate()
        let start = Date(timeIntervalSince1970: 0)
        func tick(_ bpm: Int?, _ second: Double) -> Bool {
            gate.update(bpm: bpm, limit: 150, enabled: true, now: start.addingTimeInterval(second))
        }
        XCTAssertFalse(tick(150, 0))
        XCTAssertFalse(tick(151, 1))
        XCTAssertFalse(tick(151, 2))
        XCTAssertTrue(tick(151, 3))
        XCTAssertTrue(tick(160, 4))
        for second in 5...17 { XCTAssertTrue(tick(150, Double(second))) }
        XCTAssertTrue(tick(160, 18))
        XCTAssertFalse(tick(149, 19))
        XCTAssertFalse(tick(150, 20))
        XCTAssertFalse(tick(160, 21))
        XCTAssertFalse(tick(160, 22))
        XCTAssertTrue(tick(160, 23))
        XCTAssertFalse(tick(nil, 24))
        XCTAssertFalse(tick(160, 25))
        XCTAssertFalse(tick(160, 30))
    }

    func testMissingContactAndBriefSpikesDoNotAlert() {
        var gate = MaxHRAlertGate()
        let start = Date(timeIntervalSince1970: 0)
        func tick(_ bpm: Int?, _ second: Double) -> Bool {
            gate.update(bpm: bpm, limit: 150, enabled: true, now: start.addingTimeInterval(second))
        }
        XCTAssertFalse(tick(160, 0))
        XCTAssertFalse(tick(nil, 1))
        XCTAssertFalse(tick(160, 2))
        XCTAssertFalse(tick(150, 3))
        XCTAssertFalse(tick(160, 4))
        XCTAssertFalse(tick(160, 10)) // Long notification gap resets the delay.
        XCTAssertFalse(tick(160, 11))
        XCTAssertTrue(tick(160, 12))
        gate.reset()
        XCTAssertFalse(tick(160, 13))
        XCTAssertFalse(gate.update(bpm: 160, limit: 0, enabled: true, now: start))
        XCTAssertFalse(gate.update(bpm: 160, limit: 150, enabled: false, now: start))
    }
}
