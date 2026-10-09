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

    public var habitat: GardenHabitat { GardenHabitat.allCases[plantingSeed % GardenHabitat.allCases.count] }
    public var growthTitle: String {
        guard isInRange else { return "Still to grow" }
        switch duration {
        case ...0: return "Quiet clearing"
        case ..<1_500: return "First shoots"
        case ..<3_600: return "Taking root"
        case ..<7_200: return "Flourishing"
        default: return "Established habitat"
        }
    }

    public var flowers: Int {
        guard isInRange, duration > 0 else { return 0 }
        let interval: Double = habitat == .meadow ? 360 : 900
        return min(habitat == .meadow ? 14 : 7, 1 + Int(min(duration, 10_800) / interval))
    }
    public var bushes: Int {
        guard isInRange, duration >= 600 else { return 0 }
        return min(habitat == .fernGlade ? 5 : 3, 1 + Int(min(duration - 600, 10_800) / 2_400))
    }
    public var trees: Int {
        guard isInRange, duration >= 1_500 else { return 0 }
        let interval: Double = habitat == .meadow ? 3_600 : 1_800
        return min(habitat == .meadow ? 3 : 6, 1 + Int(min(duration - 1_500, 18_000) / interval))
    }
    public var hasBerries: Bool { isInRange && habitat == .birchGrove && duration >= 2_400 }
    public var hasHive: Bool { isInRange && habitat == .meadow && duration >= 3_600 }
    public var bees: Int { hasHive ? 1 : 0 }
    public var hasFox: Bool { isInRange && habitat == .pineForest && duration >= 5_400 }
}

extension FocusActivity {
    public var gardenWeeks: [GardenWeek] {
        weeks.enumerated().map { GardenWeek(index: $0.offset, days: $0.element) }
    }
}
