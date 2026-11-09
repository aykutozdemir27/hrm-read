import SwiftUI
import Charts

struct WorkoutPanel: View {
    @ObservedObject var recorder: WorkoutRecorder
    let bpm: Int?
    let boundaries: [Int]
    let visible: Bool
    @State private var showSummary = false
    @State private var confirmFinish = false
    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Workout", systemImage: "figure.run").font(.title2.bold())
            if let error = recorder.error { Text(error).font(.footnote).foregroundStyle(.red) }
            if let session = recorder.session {
                Text(recorder.activeName).font(.headline)
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
                TextField(recorder.suggestedName, text: $recorder.draftName)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Workout name")
                Button("Start workout") {
                    recorder.start(boundaries: boundaries, bpm: bpm)
                }.buttonStyle(.borderedProminent).disabled(bpm == nil || !visible)
                if bpm == nil { Text("Connect your strap and wait for a reading to start.").font(.caption).foregroundStyle(.secondary) }
                if recorder.lastSummary != nil {
                    Button("Last workout summary") { showSummary = true }
                }
                Text("All completed workouts are saved on this phone. An unfinished workout is lost if the app closes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Saved workouts (\(recorder.workouts.count))") { showHistory = true }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .confirmationDialog("End this workout and save its summary?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("End and save summary") { recorder.finish(); showSummary = recorder.session == nil }
            Button("Keep recording", role: .cancel) {}
        }
        .sheet(isPresented: $showSummary) {
            if let summary = recorder.lastSummary { WorkoutSummaryView(summary: summary, recorder: recorder) }
        }
        .sheet(isPresented: $showHistory) { WorkoutHistoryView(recorder: recorder) }
    }
}

struct WorkoutGraph: View {
    let readings: [WorkoutReading]
    let now: Date
    var fullWorkout = false
    var started: Date? = nil
    @State private var selectedMinutes: Double?
    private var origin: Date { started ?? readings.first?.date ?? start }
    private var start: Date {
        let first = started ?? readings.first?.date ?? now
        return fullWorkout ? first : max(first, now.addingTimeInterval(-300))
    }
    private var recent: [WorkoutReading] {
        readings.filter { $0.date >= start && $0.date <= now && $0.bpm != nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fullWorkout ? "Heart rate · full workout" : "Heart rate · last 5 minutes").font(.caption).foregroundStyle(.secondary)
            if recent.isEmpty {
                Text("Waiting for readings").frame(maxWidth: .infinity, minHeight: 140).foregroundStyle(.secondary)
            } else {
                Chart(recent) { reading in
                    if let bpm = reading.bpm {
                        LineMark(x: .value("Elapsed minutes", reading.date.timeIntervalSince(started ?? readings.first?.date ?? start) / 60), y: .value("BPM", bpm),
                                 series: .value("Signal segment", reading.segment))
                            .foregroundStyle(Color.red)
                        PointMark(x: .value("Elapsed minutes", reading.date.timeIntervalSince(started ?? readings.first?.date ?? start) / 60), y: .value("BPM", bpm))
                            .foregroundStyle(Color.red).symbolSize(5)
                    }
                    if fullWorkout, reading.id == recent.first?.id, let selectedMinutes {
                        RuleMark(x: .value("Selected time", selectedMinutes))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXScale(domain: start.timeIntervalSince(started ?? readings.first?.date ?? start) / 60...max(1.0 / 60, now.timeIntervalSince(started ?? readings.first?.date ?? start) / 60))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartXAxisLabel("Elapsed minutes")
                .chartYAxisLabel("BPM")
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    if fullWorkout {
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let frame = geometry[proxy.plotAreaFrame]
                                        let x = min(max(0, value.location.x - frame.minX), frame.width)
                                        selectedMinutes = proxy.value(atX: x, as: Double.self)
                                    })
                        }
                    }
                }
                .frame(height: 150)
                .accessibilityLabel(fullWorkout ? "Heart rate graph for the full workout. Gaps indicate missing readings." : "Heart rate graph for the last five minutes. Gaps indicate missing readings.")
                if fullWorkout {
                    if let selectedMinutes {
                        let value = workoutHR(at: origin.addingTimeInterval(selectedMinutes * 60), readings: readings)
                        Text("\(workoutTime(selectedMinutes * 60)) · \(value.map { "\($0) BPM" } ?? "No reading")")
                            .font(.subheadline.monospacedDigit().bold())
                            .accessibilityAddTraits(.updatesFrequently)
                    } else {
                        Text("Touch and drag on the graph to inspect HR.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    @ObservedObject var recorder: WorkoutRecorder
    @State private var editingName = ""
    @State private var showRename = false
    private var current: WorkoutSummary { recorder.workouts.first(where: { $0.id == summary.id }) ?? summary }
    @Environment(\.dismiss) private var dismiss
    private let colors: [Color] = [.gray, .blue, .green, .orange, .red]
    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("Name", value: current.displayName)
                    Button("Rename workout") { editingName = current.displayName; showRename = true }
                    if let error = recorder.error { Text(error).foregroundStyle(.red) }
                    LabeledContent("Started", value: summary.started.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Duration", value: workoutTime(summary.duration))
                    LabeledContent("HR coverage", value: workoutTime(summary.measuredDuration))
                    LabeledContent("Without HR data", value: workoutTime(max(0, summary.duration - summary.measuredDuration)))
                }
                Section("Heart rate") {
                    LabeledContent("Average", value: summary.average.map { "\(Int($0.rounded())) BPM" } ?? "—")
                    LabeledContent("Peak", value: summary.peak.map { "\($0) BPM" } ?? "—")
                }
                Section("HR variation") {
                    if let readings = summary.readings, !readings.isEmpty {
                        WorkoutGraph(readings: readings, now: summary.ended,
                                     fullWorkout: true, started: summary.started)
                    } else {
                        Text("Graph data is unavailable for this older summary. New workouts will include a full-session graph.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
                    Text("Average HR is weighted by measured time. Missing readings and time away from the app are excluded. All completed workouts are saved locally.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Workout summary")
            .toolbar { Button("Done") { dismiss() } }
            .alert("Rename workout", isPresented: $showRename) {
                TextField("Workout name", text: $editingName)
                Button("Save") { recorder.rename(id: summary.id, name: editingName) }
                    .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: { Text("Enter a name of up to 80 characters.") }
        }
    }
}

struct WorkoutHistoryView: View {
    @ObservedObject var recorder: WorkoutRecorder
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if recorder.workouts.isEmpty { Text("Your completed workouts will appear here.").foregroundStyle(.secondary) }
                ForEach(recorder.workouts) { workout in
                    NavigationLink {
                        WorkoutSummaryView(summary: workout, recorder: recorder)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.displayName).font(.headline)
                            Text("\(workout.started.formatted(date: .abbreviated, time: .shortened)) · \(workoutTime(workout.duration))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Saved workouts")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
