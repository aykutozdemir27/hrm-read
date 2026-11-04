import Foundation
import AVFoundation
import Combine

/// Starts after two seconds above the limit, then stays active until a fresh
/// reading falls strictly below it. Missing or stale readings reset the alarm.
struct MaxHRAlertGate {
    private var aboveSince: Date?
    private var lastSample: Date?
    private(set) var isActive = false

    mutating func reset() { self = MaxHRAlertGate() }

    mutating func update(bpm: Int?, limit: Int, enabled: Bool, now: Date) -> Bool {
        guard enabled, (1...300).contains(limit), let bpm, bpm > 0 else {
            reset()
            return false
        }
        if let lastSample, now.timeIntervalSince(lastSample) > 3 { reset() }
        lastSample = now
        if bpm < limit { reset(); return false }
        if isActive { return true }
        // Equality keeps an existing alarm sounding, but cannot start one.
        guard bpm > limit else { aboveSince = nil; return false }
        if aboveSince == nil { aboveSince = now }
        guard now.timeIntervalSince(aboveSince!) >= 2 else { return false }
        isActive = true
        return true
    }
}

final class AlertSound: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var isLooping = false

    func play(looping: Bool = false) {
        // Repeated HR samples must not restart the ongoing beep pattern.
        if isLooping, player?.isPlaying == true { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.tone())
            self.player = player
            isLooping = looping
            player.numberOfLoops = looping ? -1 : 0
            player.delegate = self
            player.volume = 0.7
            guard player.play() else { throw NSError(domain: "AlertSound", code: 1) }
            error = nil
        } catch {
            self.error = "Sound unavailable. Check audio output and use Test sound."
            stop()
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        isLooping = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player { stop() }
    }

    private static func tone() -> Data {
        let rate = 22050
        let count = rate // Two short beeps across one second.
        var samples = Data()
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let local = t.truncatingRemainder(dividingBy: 0.5)
            let envelope = local < 0.25 ? min(1, local / 0.01, (0.25 - local) / 0.01) : 0
            var value = Int16(sin(2 * .pi * 880 * t) * 12000 * max(0, envelope)).littleEndian
            withUnsafeBytes(of: &value) { samples.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        u32(UInt32(36 + samples.count)); wav.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        wav.append(Data("data".utf8)); u32(UInt32(samples.count)); wav.append(samples)
        return wav
    }
}
