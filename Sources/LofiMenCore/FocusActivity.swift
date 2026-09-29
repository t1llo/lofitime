import Foundation

public struct ActivityDay: Identifiable, Sendable {
    public let date: Date
    public let duration: TimeInterval
    public let sessions: Int
    public let isInRange: Bool
    public var id: Date { date }

    public var level: Int {
        switch duration {
        case ...0: 0
        case ...1_500: 1
        case ...3_000: 2
        case ...6_000: 3
        default: 4
        }
    }
}

/// A rolling year of local-calendar days, laid out Sunday-first like GitHub.
public struct FocusActivity: Sendable {
    public let weeks: [[ActivityDay]]
    public let startDate: Date
    public let endDate: Date
    public let totalDuration: TimeInterval
    public let totalSessions: Int
    public let activeDays: Int

    public init(records: [SessionRecord], through now: Date, calendar: Calendar = .current) {
        let endDate = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -364, to: endDate)!
        self.endDate = endDate
        self.startDate = startDate
        let gridStart = calendar.date(byAdding: .day,
                                      value: 1 - calendar.component(.weekday, from: startDate), to: startDate)!
        let visible = records.filter { $0.finishedAt >= startDate && $0.finishedAt <= now }
        let grouped = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.finishedAt) }
        let days = (0..<371).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            let sessions = grouped[date] ?? []
            return ActivityDay(date: date,
                               duration: sessions.reduce(0) { $0 + max(0, $1.duration) },
                               sessions: sessions.count,
                               isInRange: date >= startDate && date <= endDate)
        }
        weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<($0 + 7)]) }
        totalDuration = visible.reduce(0) { $0 + max(0, $1.duration) }
        totalSessions = visible.count
        activeDays = days.filter { $0.isInRange && $0.sessions > 0 }.count
    }
}
