import XCTest
@testable import HRMRead

final class WorkoutTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1000)
    func testWeightedAverageGapsAndZones() {
        var workout = WorkoutSession(started: start, boundaries: [100, 120, 140, 160])
        workout.record(100, at: start)
        workout.record(160, at: start.addingTimeInterval(2))
        workout.record(nil, at: start.addingTimeInterval(3))
        workout.record(140, at: start.addingTimeInterval(10))
        let result = workout.summary(at: start.addingTimeInterval(20))
        XCTAssertEqual(result.duration, 20)
        XCTAssertEqual(result.measuredDuration, 6)
        XCTAssertEqual(result.average!, 130, accuracy: 0.001)
        XCTAssertEqual(result.peak, 160)
        XCTAssertEqual(result.zoneSeconds, [0, 2, 0, 3, 1])
        XCTAssertNotEqual(workout.readings[1].segment, workout.readings[3].segment)
    }

    func testNoDataAndNoZones() {
        var workout = WorkoutSession(started: start, boundaries: [])
        XCTAssertNil(workout.summary(at: start).average)
        workout.record(80, at: start)
        workout.record(90, at: start.addingTimeInterval(10))
        XCTAssertNotEqual(workout.readings[0].segment, workout.readings[1].segment)
        let result = workout.summary(at: start.addingTimeInterval(11))
        XCTAssertEqual(result.measuredDuration, 4)
        XCTAssertEqual(result.zoneSeconds, [0, 0, 0, 0, 0])
    }

    func testSummaryPersistsAndStartCannotOverwriteActiveWorkout() {
        let name = "WorkoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let recorder = WorkoutRecorder(defaults: defaults)
        recorder.start(boundaries: [100, 120, 140, 160], bpm: 110, now: start)
        recorder.start(boundaries: [], bpm: 200, now: start.addingTimeInterval(1))
        recorder.record(nil, now: start.addingTimeInterval(2))
        recorder.finish(now: start.addingTimeInterval(10))
        XCTAssertNil(recorder.session)
        let restored = WorkoutRecorder(defaults: defaults).lastSummary!
        XCTAssertEqual(restored.average, 110)
        XCTAssertEqual(restored.measuredDuration, 2)
        XCTAssertEqual(restored.duration, 10)
        XCTAssertEqual(restored.boundaries, [100, 120, 140, 160])
    }
}
