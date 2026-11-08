import Foundation
import Combine

struct WorkoutReading: Identifiable, Codable {
    let id: Int
    let date: Date
    let bpm: Int?
    let segment: Int
}

struct WorkoutSummary: Identifiable, Codable {
    let id: UUID
    let started: Date
    let ended: Date
    let duration: TimeInterval
    let measuredDuration: TimeInterval
    let average: Double?
    let peak: Int?
    let zoneSeconds: [TimeInterval]
    let boundaries: [Int]
}

/// Integrates each reading for at most three seconds. Gaps and app inactivity
/// contribute to elapsed time, but never to measured time or HR statistics.
struct WorkoutSession {
    let started: Date
    let boundaries: [Int]
    private(set) var readings: [WorkoutReading] = []
    private var segment = 0

    init(started: Date, boundaries: [Int]) {
        self.started = started
        self.boundaries = boundaries
    }

    mutating func record(_ bpm: Int?, at date: Date) {
        guard date >= started, readings.last.map({ date >= $0.date }) ?? true else { return }
        let value = bpm.flatMap { $0 > 0 ? $0 : nil }
        if value == nil || readings.last?.bpm == nil ||
            readings.last.map({ date.timeIntervalSince($0.date) > 3 }) == true { segment += 1 }
        readings.append(WorkoutReading(id: readings.count, date: date, bpm: value, segment: segment))
    }

    func summary(at end: Date) -> WorkoutSummary {
        let end = max(started, end)
        var measured = 0.0, weighted = 0.0
        var zones = Array(repeating: 0.0, count: 5)
        var peak: Int?
        for (index, reading) in readings.enumerated() where reading.date <= end {
            guard let bpm = reading.bpm else { continue }
            peak = max(peak ?? bpm, bpm)
            let next = index + 1 < readings.count ? readings[index + 1].date : end
            let seconds = max(0, min(3, min(next, end).timeIntervalSince(reading.date)))
            measured += seconds
            weighted += Double(bpm) * seconds
            if let zone = HeartRateZones.zone(bpm: bpm, boundaries: boundaries) { zones[zone - 1] += seconds }
        }
        return WorkoutSummary(id: UUID(), started: started, ended: end,
                              duration: end.timeIntervalSince(started), measuredDuration: measured,
                              average: measured > 0 ? weighted / measured : nil, peak: peak,
                              zoneSeconds: zones, boundaries: boundaries)
    }
}

final class WorkoutRecorder: ObservableObject {
    @Published private(set) var session: WorkoutSession?
    @Published private(set) var lastSummary: WorkoutSummary?
    private let defaults: UserDefaults
    private let summaryKey = "lastWorkoutSummary.v03"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: summaryKey) {
            lastSummary = try? JSONDecoder().decode(WorkoutSummary.self, from: data)
        }
    }

    func start(boundaries: [Int], bpm: Int?, now: Date = Date()) {
        guard session == nil else { return }
        var newSession = WorkoutSession(started: now, boundaries: boundaries)
        newSession.record(bpm, at: now)
        session = newSession
    }

    func record(_ bpm: Int?, now: Date = Date()) {
        guard var current = session else { return }
        current.record(bpm, at: now)
        session = current
    }

    func finish(now: Date = Date()) {
        guard let session else { return }
        let summary = session.summary(at: now)
        lastSummary = summary
        self.session = nil
        if let data = try? JSONEncoder().encode(summary) { defaults.set(data, forKey: summaryKey) }
    }
}

func workoutTime(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
}
