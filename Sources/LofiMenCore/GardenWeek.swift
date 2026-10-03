import Foundation

public struct GardenWeek: Identifiable, Sendable {
    public let index: Int
    public let days: [ActivityDay]
    public var id: Date { days[0].date }
    public var duration: TimeInterval { days.reduce(0) { $0 + $1.duration } }
    public var sessions: Int { days.reduce(0) { $0 + $1.sessions } }
    public var activeDays: Int { days.filter { $0.sessions > 0 }.count }

    public init(index: Int, days: [ActivityDay]) {
        self.index = index
        self.days = days
    }
}

extension ActivityDay {
    /// A stable seed keeps each day's planting varied without rerolling on redraw
    /// or when the calendar advances to a new week. Swift's randomized Hasher
    /// cannot be used here because the forest should survive app relaunches.
    public var plantingSeed: Int {
        var seed = UInt64(bitPattern: Int64(date.timeIntervalSince1970)) &+ 0x9E3779B97F4A7C15
        seed = (seed ^ (seed >> 30)) &* 0xBF58476D1CE4E5B9
        seed = (seed ^ (seed >> 27)) &* 0x94D049BB133111EB
        return Int((seed ^ (seed >> 31)) & 0xFFFF)
    }

    public var flowers: Int {
        guard duration > 0 else { return 0 }
        let base = Int(ceil(min(duration, 1_800) / 300))
        return min(8, base + (duration >= 600 ? plantingSeed % 3 : 0))
    }
    public var bushes: Int { duration >= 600 ? 1 + (duration >= 1_800 ? (plantingSeed / 3) % 2 : 0) : 0 }
    public var trees: Int {
        // Some days grow their first tree in 15–20 minutes, others in 25–30.
        // Longer sessions add companions, rather than requiring hours for a tree.
        let firstTree = TimeInterval(900 + (plantingSeed % 4) * 300)
        guard duration >= firstTree else { return 0 }
        return min(3, 1 + Int(min(duration - firstTree, 2_400) / 1_200))
    }
    public var hasBerries: Bool { duration >= 900 }
    public var hasHive: Bool { duration >= TimeInterval(1_800 + (plantingSeed / 7 % 3) * 300) }
    public var bees: Int { hasHive ? 1 : 0 }
    public var hasFox: Bool { duration >= TimeInterval(2_700 + (plantingSeed / 11 % 3) * 300) }
}

extension FocusActivity {
    public var gardenWeeks: [GardenWeek] {
        weeks.enumerated().map { GardenWeek(index: $0.offset, days: $0.element) }
    }
}
