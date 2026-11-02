import XCTest
@testable import HRMRead

final class HeartRateTests: XCTestCase {
    func testMeasurementFormatsAndTruncation() {
        XCTAssertEqual(HeartRateMeasurement(data: Data([0, 72]))?.bpm, 72)
        XCTAssertEqual(HeartRateMeasurement(data: Data([1, 44, 1]))?.bpm, 300)
        XCTAssertNil(HeartRateMeasurement(data: Data([])))
        XCTAssertNil(HeartRateMeasurement(data: Data([1, 44])))
        XCTAssertEqual(HeartRateMeasurement(data: Data([6, 80]))?.contactDetected, true)
        XCTAssertEqual(HeartRateMeasurement(data: Data([4, 80]))?.contactDetected, false)
        XCTAssertNil(HeartRateMeasurement(data: Data([0, 80]))?.contactDetected)
    }
    func testZoneEdgesAndInvalidConfiguration() {
        let edges = [100, 120, 140, 160]
        XCTAssertEqual(HeartRateZones.zone(bpm: 99, boundaries: edges), 1)
        XCTAssertEqual(HeartRateZones.zone(bpm: 100, boundaries: edges), 2)
        XCTAssertEqual(HeartRateZones.zone(bpm: 159, boundaries: edges), 4)
        XCTAssertEqual(HeartRateZones.zone(bpm: 160, boundaries: edges), 5)
        XCTAssertNil(HeartRateZones.zone(bpm: 0, boundaries: edges))
        XCTAssertFalse(HeartRateZones.isValid([100, 100, 140, 160]))
        XCTAssertFalse(HeartRateZones.isValid([100, 90, 140, 160]))
        XCTAssertFalse(HeartRateZones.isValid([100, 120]))
    }
}
