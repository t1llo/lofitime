import Foundation

public struct ActivityDay: Identifiable, Sendable {
    public let date: Date
    public let duration: TimeInterval
    public let sessions: Int
    public let isInRange: Bool
    public var id: Date { date }

    public init(date: Date, duration: TimeInterval, sessions: Int, isInRange: Bool) {
        self.date = date
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.sessions = max(0, sessions)
        self.isInRange = isInRange
    }

    public var level: Int {
        switch duration {
        case ...0: 0
        case ..<1_500: 1
        case ..<3_600: 2
        case ..<7_200: 3
        default: 4
        }
    }
}

/// Three complete Sunday-first rows, ending with the current week or a historical week.
public struct FocusActivity: Sendable {
    public static let historyWeeks = 3
    public static let historyDays = historyWeeks * 7
    public let weeks: [[ActivityDay]]
    public let startDate: Date
    public let endDate: Date
    public let totalDuration: TimeInterval
    public let totalSessions: Int
    public let activeDays: Int

    /// A negative offset browses older weeks without treating later records as part of that window.
    public init(records: [SessionRecord], through now: Date, calendar: Calendar = .current, weekOffset: Int = 0) {
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: today), to: today)!
        let currentWeekStart = calendar.date(byAdding: .weekOfYear, value: min(0, weekOffset), to: thisWeek)!
        let startDate = calendar.date(byAdding: .day, value: -(Self.historyWeeks - 1) * 7, to: currentWeekStart)!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: currentWeekStart)!
        self.endDate = min(today, calendar.date(byAdding: .day, value: -1, to: nextWeek)!)
        self.startDate = startDate
        let visible = records.filter {
            $0.duration.isFinite && $0.duration > 0 &&
                $0.finishedAt >= startDate && $0.finishedAt < nextWeek && $0.finishedAt <= now
        }
        let grouped = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.finishedAt) }
        let gridDayCount = Self.historyDays
        let days = (0..<gridDayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDate)!
            let sessions = grouped[date] ?? []
            return ActivityDay(date: date,
                               duration: sessions.reduce(0) { $0 + max(0, $1.duration) },
                               sessions: sessions.count,
                               isInRange: date <= today)
        }
        weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<($0 + 7)]) }
        totalDuration = visible.reduce(0) { $0 + max(0, $1.duration) }
        totalSessions = visible.count
        activeDays = days.filter { $0.isInRange && $0.sessions > 0 }.count
    }
}
