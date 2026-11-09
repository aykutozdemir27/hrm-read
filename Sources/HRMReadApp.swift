import SwiftUI
import UIKit

@main
struct HRMReadApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @StateObject private var monitor = BluetoothMonitor()
    @AppStorage("zoneBoundaries") private var savedZones = ""
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("maxHRAlertEnabled") private var maxHRAlertEnabled = false
    @AppStorage("maxHRLimit") private var maxHRLimit = ""
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sound = AlertSound()
    @StateObject private var workout = WorkoutRecorder()
    @State private var alertGate = MaxHRAlertGate()
    @State private var showSettings = false
    private var boundaries: [Int] { savedZones.split(separator: ",").compactMap { Int($0) } }
    private var zone: Int? { monitor.bpm.flatMap { HeartRateZones.zone(bpm: $0, boundaries: boundaries) } }
    private let colors: [Color] = [.gray, .blue, .green, .orange, .red]
    private var limit: Int { Int(maxHRLimit) ?? 0 }
    private var aboveLimit: Bool { maxHRAlertEnabled && (1...300).contains(limit) && (monitor.bpm ?? 0) > limit }
    private var sessionActive: Bool { monitor.connected || monitor.busy || monitor.scanning }

    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && sessionActive && scenePhase == .active
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Label("HEART RATE", systemImage: "heart.fill")
                        .font(.headline).foregroundStyle(.secondary)
                    Text(monitor.bpm.map(String.init) ?? "—")
                        .font(.system(size: 100, weight: .bold, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                        .accessibilityLabel(monitor.bpm.map { "\($0) beats per minute" } ?? "No current heart rate")
                    Text("BPM").font(.title3).foregroundStyle(.secondary)
                    if maxHRAlertEnabled && (1...300).contains(limit) {
                        Label(alertGate.isActive ? "HR alarm · return below \(limit) BPM" : (aboveLimit ? "Above your \(limit) BPM limit" : "HR alert above \(limit) BPM"),
                              systemImage: aboveLimit || alertGate.isActive ? "exclamationmark.circle.fill" : "bell")
                            .foregroundStyle(aboveLimit || alertGate.isActive ? Color.red : Color.secondary)
                            .font(.headline).multilineTextAlignment(.center)
                    }
                    if let error = sound.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    VStack(spacing: 12) {
                        Text(zone.map { "ZONE \($0)" } ?? (HeartRateZones.isValid(boundaries) ? "Waiting for heart rate" : "Set your zones"))
                            .font(.title2.bold())
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { number in
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(colors[number - 1].opacity(zone == number ? 1 : 0.2))
                                    .frame(height: zone == number ? 24 : 12)
                            }
                        }.frame(height: 24)
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    Text(monitor.status).font(.callout).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)
                    if monitor.connected || monitor.busy || monitor.scanning {
                        Button("Disconnect / Stop") { monitor.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Find strap") { monitor.scan() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    if !monitor.connected && !monitor.busy {
                        ForEach(monitor.devices, id: \.identifier) { device in
                            Button { monitor.connect(device) } label: {
                                HStack {
                                    Image(systemName: "sensor.fill")
                                    VStack(alignment: .leading) {
                                        Text(device.name ?? "Heart rate strap")
                                        Text(String(device.identifier.uuidString.suffix(8))).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }.padding()
                            }.buttonStyle(.bordered)
                        }
                    }
                    WorkoutPanel(recorder: workout, bpm: monitor.bpm, boundaries: boundaries,
                                 visible: scenePhase == .active)
                    Text("Wear the strap with moist electrodes. Use its open connection mode. Keep this app on screen for live readings.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24)
            }
            .navigationTitle("HRM Read")
            .toolbar { Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings") }
            .sheet(isPresented: $showSettings) { ZoneSettings(savedZones: $savedZones, sound: sound) }
        }
        .onAppear { updateScreenAwake() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; sound.stop(); alertGate.reset() }
        .onChange(of: sessionActive) { _ in updateScreenAwake() }
        .onChange(of: keepScreenAwake) { _ in updateScreenAwake() }
        .onChange(of: scenePhase) { phase in
            updateScreenAwake()
            if phase != .active { alertGate.reset(); sound.stop(); workout.record(nil) }
        }
        .onChange(of: maxHRLimit) { _ in alertGate.reset(); sound.stop() }
        .onChange(of: maxHRAlertEnabled) { _ in alertGate.reset(); sound.stop() }
        .onReceive(monitor.$bpm) { bpm in
            workout.record(scenePhase == .active ? bpm : nil)
            if alertGate.update(bpm: bpm, limit: limit,
                                enabled: maxHRAlertEnabled && scenePhase == .active, now: Date()) {
                sound.play(looping: true)
            } else { sound.stop() }
        }
    }
}

struct ZoneSettings: View {
    @Binding var savedZones: String
    @ObservedObject var sound: AlertSound
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("maxHRAlertEnabled") private var maxHRAlertEnabled = false
    @AppStorage("maxHRLimit") private var maxHRLimit = ""
    @Environment(\.dismiss) private var dismiss
    @State private var entries = ["", "", "", ""]
    private var values: [Int] { entries.compactMap { Int($0) } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Keep screen awake", isOn: $keepScreenAwake)
                    Text("While scanning, connecting, or connected with this app visible. Stops when you disconnect or leave the app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    TextField("Maximum HR limit (BPM)", text: $maxHRLimit).keyboardType(.numberPad)
                    Toggle("Maximum HR sound alert", isOn: $maxHRAlertEnabled)
                        .disabled(!maxHRAlertEnabled && !(1...300).contains(Int(maxHRLimit) ?? 0))
                    Button("Test sound") { sound.play() }
                    if let error = sound.error { Text(error).foregroundStyle(.red) }
                } header: { Text("Maximum HR alert") } footer: {
                    Text("Enter your own limit (1–300 BPM). After 2 seconds above it, beeping continues until HR drops strictly below it. At exactly the limit, an active alarm keeps sounding. Signal loss, disabling the alert, or leaving the app stops it. Uses media volume and your current audio output, including in silent mode. Keep the app visible. These options save immediately.")
                }
                Section {
                    ForEach(0..<4, id: \.self) { index in
                        HStack {
                            Text("Zone \(index + 2) starts at")
                            Spacer()
                            TextField("BPM", text: $entries[index])
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                                .accessibilityLabel("Zone \(index + 2) lower boundary in BPM")
                        }
                    }
                } footer: {
                    Text("Enter your existing Garmin zone boundaries in increasing order (1–300 BPM). Zone 1 includes positive readings below Zone 2. Zone 5 includes all readings at or above its boundary. No age-based zones are assumed.")
                }
                if !HeartRateZones.isValid(values) {
                    Text("Enter four different numbers in increasing order.").foregroundStyle(.secondary)
                }
                Section { Text("HRM Read 0.4.0").foregroundStyle(.secondary) }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savedZones = values.map(String.init).joined(separator: ","); dismiss() }
                        .disabled(!HeartRateZones.isValid(values))
                }
            }
            .onAppear {
                let existing = savedZones.split(separator: ",").map(String.init)
                if existing.count == 4 { entries = existing }
            }
        }
    }
}
