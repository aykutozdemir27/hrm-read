import SwiftUI
import Charts

struct WorkoutPanel: View {
    @ObservedObject var recorder: WorkoutRecorder
    let bpm: Int?
    let boundaries: [Int]
    let visible: Bool
    @State private var showSummary = false
    @State private var confirmFinish = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Workout", systemImage: "figure.run").font(.title2.bold())
            if let session = recorder.session {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let summary = session.summary(at: context.date)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workoutTime(summary.duration)).font(.largeTitle.monospacedDigit().bold())
                        HStack {
                            Text("Avg \(summary.average.map { String(Int($0.rounded())) } ?? "—")")
                            Spacer()
                            Text("Peak \(summary.peak.map(String.init) ?? "—") BPM")
                        }.font(.subheadline).foregroundStyle(.secondary)
                        WorkoutGraph(readings: session.readings, now: context.date)
                    }
                }
                Button("End workout", role: .destructive) { confirmFinish = true }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
                Text("Signal gaps are excluded from HR statistics. Keep the app visible. Your zones at the start are used for this workout.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Record a session to see your HR trend and time in each zone.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Start workout") {
                    recorder.start(boundaries: boundaries, bpm: bpm)
                }.buttonStyle(.borderedProminent).disabled(bpm == nil || !visible)
                if bpm == nil { Text("Connect your strap and wait for a reading to start.").font(.caption).foregroundStyle(.secondary) }
                if recorder.lastSummary != nil {
                    Button("Last workout summary") { showSummary = true }
                }
                Text("Only the latest completed summary is saved on this phone. An unfinished workout is lost if the app closes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .confirmationDialog("End this workout and save its summary?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("End and save summary") { recorder.finish(); showSummary = true }
            Button("Keep recording", role: .cancel) {}
        }
        .sheet(isPresented: $showSummary) {
            if let summary = recorder.lastSummary { WorkoutSummaryView(summary: summary) }
        }
    }
}

struct WorkoutGraph: View {
    let readings: [WorkoutReading]
    let now: Date
    private var recent: [WorkoutReading] {
        readings.filter { $0.date >= now.addingTimeInterval(-600) && $0.bpm != nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart rate · last 10 minutes").font(.caption).foregroundStyle(.secondary)
            if recent.isEmpty {
                Text("Waiting for readings").frame(maxWidth: .infinity, minHeight: 140).foregroundStyle(.secondary)
            } else {
                Chart(recent) { reading in
                    if let bpm = reading.bpm {
                        LineMark(x: .value("Time", reading.date), y: .value("BPM", bpm),
                                 series: .value("Signal segment", reading.segment))
                            .foregroundStyle(Color.red)
                        PointMark(x: .value("Time", reading.date), y: .value("BPM", bpm))
                            .foregroundStyle(Color.red).symbolSize(5)
                    }
                }
                .chartXScale(domain: max(readings.first?.date ?? now, now.addingTimeInterval(-600))...now.addingTimeInterval(1))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(.hidden)
                .frame(height: 150)
                .accessibilityLabel("Heart rate graph for the last ten minutes. Gaps indicate missing readings.")
            }
        }
    }
}

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss
    private let colors: [Color] = [.gray, .blue, .green, .orange, .red]
    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("Started", value: summary.started.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Duration", value: workoutTime(summary.duration))
                    LabeledContent("HR coverage", value: workoutTime(summary.measuredDuration))
                    LabeledContent("Without HR data", value: workoutTime(max(0, summary.duration - summary.measuredDuration)))
                }
                Section("Heart rate") {
                    LabeledContent("Average", value: summary.average.map { "\(Int($0.rounded())) BPM" } ?? "—")
                    LabeledContent("Peak", value: summary.peak.map { "\($0) BPM" } ?? "—")
                }
                if HeartRateZones.isValid(summary.boundaries) {
                    Section {
                        ForEach(0..<5, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Zone \(index + 1)")
                                    Spacer()
                                    Text(workoutTime(summary.zoneSeconds[index])).monospacedDigit()
                                }
                                ProgressView(value: summary.zoneSeconds[index], total: max(1, summary.measuredDuration))
                                    .tint(colors[index])
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("Time in zones") } footer: {
                        Text("Using the boundaries saved when the workout started: \(summary.boundaries.map(String.init).joined(separator: ", ")) BPM.")
                    }
                } else {
                    Section { Text("Zone time is unavailable because zones were not configured when this workout started.") }
                }
                Section {
                    Text("Average HR is weighted by measured time. Missing readings and time away from the app are excluded. Only the latest completed summary is saved locally.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Workout summary")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
