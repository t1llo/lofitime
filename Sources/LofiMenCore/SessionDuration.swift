import Foundation

public enum SessionDuration {
    /// Plain numbers are minutes; a colon accepts exact minutes and seconds.
    /// Valid durations run from one second through three hours.
    public static func parse(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let minutes = Int(parts[0]), (0...180).contains(minutes) else { return nil }
        let seconds = parts.count == 2 ? Int(parts[1]) : 0
        guard let seconds, (0..<60).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        guard (1...10_800).contains(total) else { return nil }
        return TimeInterval(total)
    }

    public static func clock(_ duration: TimeInterval) -> String {
        let seconds = Int(ceil(max(0, duration)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public static func summary(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration))
        if seconds == 0 { return "0m" }
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        let remainder = seconds % 60
        return [hours > 0 ? "\(hours)h" : nil,
                minutes > 0 ? "\(minutes)m" : nil,
                remainder > 0 ? "\(remainder)s" : nil]
            .compactMap { $0 }.joined(separator: " ")
    }
}
