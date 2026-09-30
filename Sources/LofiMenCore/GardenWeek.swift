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
    public var flowers: Int { duration > 0 ? min(5, max(1, Int(ceil(duration / 1_500)))) : 0 }
    public var bushes: Int { duration >= 3_600 ? 1 : 0 }
    public var trees: Int { duration >= 7_200 ? 1 : 0 }
    public var hasBerries: Bool { duration >= 5_400 }
    public var hasHive: Bool { duration >= 10_800 }
    public var bees: Int { hasHive ? 1 : 0 }
    public var hasFox: Bool { duration >= 14_400 }
}

extension FocusActivity {
    public var gardenWeeks: [GardenWeek] {
        weeks.enumerated().map { GardenWeek(index: $0.offset, days: $0.element) }
    }
}
