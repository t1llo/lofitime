import Foundation

public struct ActivityDay: Identifiable, Sendable {
    public let date: Date
    public let duration: TimeInterval
    public let sessions: Int
    public let isInRange: Bool
    public var id: Date { date }

    public init(date: Date, duration: TimeInterval, sessions: Int, isInRange: Bool) {
        self.date = date
        self.duration = duration
        self.sessions = sessions
        self.isInRange = isInRange
    }

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

/// The last 30 local-calendar days, arranged in Sunday-first weeks.
public struct FocusActivity: Sendable {
    public static let historyDays = 30
    public let weeks: [[ActivityDay]]
    public let startDate: Date
    public let endDate: Date
    public let totalDuration: TimeInterval
    public let totalSessions: Int
    public let activeDays: Int

    public init(records: [SessionRecord], through now: Date, calendar: Calendar = .current) {
        let endDate = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: 1 - Self.historyDays, to: endDate)!
        self.endDate = endDate
        self.startDate = startDate
        let gridStart = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: startDate), to: startDate)!
        let visible = records.filter { $0.finishedAt >= startDate && $0.finishedAt <= now }
        let grouped = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.finishedAt) }
        let dayCount = calendar.dateComponents([.day], from: gridStart, to: endDate).day! + 1
        let gridDayCount = ((dayCount + 6) / 7) * 7
        let days = (0..<gridDayCount).map { offset in
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
