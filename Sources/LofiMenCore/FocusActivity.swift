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
}

/// Calendar-based totals. The end is exclusive, so adjacent periods never double-count a session.
public struct ActivityPeriod: Sendable {
    public let days: [ActivityDay]
    public let startDate: Date
    public let endDate: Date
    public let totalDuration: TimeInterval
    public let totalSessions: Int
    public let activeDays: Int
    public var dailyAverage: TimeInterval { totalDuration / Double(max(1, days.filter(\.isInRange).count)) }

    init(records: [SessionRecord], interval: DateInterval, now: Date, calendar: Calendar) {
        startDate = interval.start
        endDate = interval.end
        let today = calendar.startOfDay(for: now)
        let visible = records.filter { $0.finishedAt >= interval.start && $0.finishedAt < interval.end }
        let grouped = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.finishedAt) }
        let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        days = (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: interval.start)!
            let sessions = grouped[date] ?? []
            return ActivityDay(date: date,
                               duration: sessions.reduce(0) { $0 + $1.duration },
                               sessions: sessions.count, isInRange: date <= today)
        }
        totalDuration = visible.reduce(0) { $0 + $1.duration }
        totalSessions = visible.count
        activeDays = days.filter { $0.sessions > 0 }.count
    }
}

/// The room uses recent focus; these permanent statistics always use the complete saved history.
public struct FocusActivity: Sendable {
    public let endDate: Date
    public let updatedAt: Date
    public let week: ActivityPeriod
    public let month: ActivityPeriod
    public let allTimeDuration: TimeInterval
    public let firstSessionDate: Date?
    public var canGoToPreviousWeek: Bool { firstSessionDate.map { $0 < week.startDate } ?? false }
    public var canGoToPreviousMonth: Bool { firstSessionDate.map { $0 < month.startDate } ?? false }

    public init(records: [SessionRecord], through now: Date, calendar: Calendar = .current,
                weekOffset: Int = 0, monthOffset: Int = 0) {
        let valid = records.filter { $0.duration.isFinite && $0.duration > 0 && $0.finishedAt <= now }
        updatedAt = now
        endDate = calendar.startOfDay(for: now)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!
        let weekDate = calendar.date(byAdding: .weekOfYear, value: min(0, weekOffset), to: thisWeek.start)!
        let thisMonth = calendar.dateInterval(of: .month, for: now)!
        let monthDate = calendar.date(byAdding: .month, value: min(0, monthOffset), to: thisMonth.start)!
        week = ActivityPeriod(records: valid, interval: calendar.dateInterval(of: .weekOfYear, for: weekDate)!, now: now, calendar: calendar)
        month = ActivityPeriod(records: valid, interval: calendar.dateInterval(of: .month, for: monthDate)!, now: now, calendar: calendar)
        allTimeDuration = valid.reduce(0) { $0 + $1.duration }
        firstSessionDate = valid.map(\.finishedAt).min()
    }
}
