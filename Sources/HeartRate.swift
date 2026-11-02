import Foundation

struct HeartRateMeasurement: Equatable {
    let bpm: Int
    let contactDetected: Bool?

    init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count >= 2 else { return nil }
        let flags = bytes[0]
        if flags & 1 != 0 {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            bpm = Int(bytes[1])
        }
        contactDetected = flags & 4 != 0 ? flags & 2 != 0 : nil
    }
}

enum HeartRateZones {
    // Four user-entered lower boundaries divide the five zones.
    static func isValid(_ boundaries: [Int]) -> Bool {
        boundaries.count == 4 && boundaries.allSatisfy { (1...300).contains($0) }
            && zip(boundaries, boundaries.dropFirst()).allSatisfy { $0 < $1 }
    }

    static func zone(bpm: Int, boundaries: [Int]) -> Int? {
        guard bpm > 0, isValid(boundaries) else { return nil }
        return 1 + boundaries.filter { bpm >= $0 }.count
    }
}
