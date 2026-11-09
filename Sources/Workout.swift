import Foundation
import Combine

struct WorkoutReading: Identifiable, Codable {
    let id: Int
    let date: Date
    let bpm: Int?
    let segment: Int
}

func workoutHR(at date: Date, readings: [WorkoutReading]) -> Int? {
    guard let reading = readings.last(where: { $0.date <= date }),
          date.timeIntervalSince(reading.date) <= 3 else { return nil }
    return reading.bpm
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
    // Optional so summaries saved by v0.3 remain readable.
    var readings: [WorkoutReading]?
    var name: String?
    var displayName: String { name ?? "Workout \(started.formatted(date: .abbreviated, time: .shortened))" }
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
                              zoneSeconds: zones, boundaries: boundaries,
                              readings: readings.filter { $0.date <= end })
    }
}

final class WorkoutRecorder: ObservableObject {
    @Published private(set) var session: WorkoutSession?
    @Published private(set) var workouts: [WorkoutSummary] = []
    @Published private(set) var error: String?
    @Published var draftName = ""
    @Published private(set) var activeName = ""
    var lastSummary: WorkoutSummary? { workouts.first }
    private let defaults: UserDefaults
    private let directory: URL
    private let summaryKey = "lastWorkoutSummary.v03"
    var suggestedName: String { "Workout \(max(1, defaults.integer(forKey: "nextWorkoutNumber")))" }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Workouts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                do { workouts.append(try JSONDecoder().decode(WorkoutSummary.self, from: Data(contentsOf: file))) }
                catch { self.error = "A saved workout could not be opened. Its file has been kept." }
            }
            if let data = defaults.data(forKey: summaryKey), let old = try? JSONDecoder().decode(WorkoutSummary.self, from: data), !workouts.contains(where: { $0.id == old.id }) {
                try write(old)
                workouts.append(old)
            }
            workouts.sort { $0.started > $1.started }
        } catch { self.error = "Workout storage is unavailable. \(error.localizedDescription)" }
    }

    private func write(_ workout: WorkoutSummary) throws {
        let data = try JSONEncoder().encode(workout)
        try data.write(to: directory.appendingPathComponent(workout.id.uuidString + ".json"), options: .atomic)
    }

    func start(boundaries: [Int], bpm: Int?, now: Date = Date()) {
        guard session == nil else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        activeName = trimmed.isEmpty ? suggestedName : String(trimmed.prefix(80))
        defaults.set(max(1, defaults.integer(forKey: "nextWorkoutNumber")) + 1, forKey: "nextWorkoutNumber")
        draftName = ""
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
        var summary = session.summary(at: now)
        summary.name = activeName
        do {
            try write(summary)
            workouts.insert(summary, at: 0)
            self.session = nil
            error = nil
        } catch { self.error = "Could not save workout. Keep the app open and try End workout again." }
    }

    func rename(id: UUID, name: String) {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = workouts[index]
        updated.name = String(trimmed.prefix(80))
        do { try write(updated); workouts[index] = updated; error = nil }
        catch { self.error = "Could not save the new name. Please try again." }
    }
}

func workoutTime(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
}
