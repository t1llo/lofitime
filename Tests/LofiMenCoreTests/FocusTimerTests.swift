import Foundation
import LofiMenCore

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, line: UInt = #line) throws {
    guard actual == expected else {
        throw TestFailure(description: "Line \(line): expected \(expected), got \(actual)")
    }
}

@main
struct FocusTimerTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let configuration = FocusConfiguration()

    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("Pause and resume preserve remaining time", pauseAndResume),
            ("Sleep completes once without inventing sessions", sleepAndCompletion),
            ("Fourth focus session starts a long break", longBreakCycle),
            ("Skipping and resetting never count as completed work", skipAndReset),
            ("Settings preserve an active session's duration", activeConfiguration),
            ("Running timer survives persistence and relaunch", persistence),
            ("Auto-start and configuration bounds", autoStartAndBounds),
            ("Paused timers cannot complete", pausedCompletion),
            ("Completion boundary and repeated start are exact", exactBoundary),
            ("Typed durations accept exact seconds and reject invalid input", durationInput),
            ("Custom durations persist, reset, and complete precisely", customDuration),
            ("Activity aggregates sessions over the last 60 days", activityAggregation),
            ("Activity excludes old and future records", activityRange),
            ("Activity respects local days across daylight-saving changes", activityTimeZone),
            ("Existing preferences migrate and theme choice persists", preferenceMigration)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                fputs("FAIL: \(name) — \(error)\n", stderr)
            }
        }
        print("\n\(tests.count - failures)/\(tests.count) tests passed.")
        if failures > 0 { exit(1) }
    }

    static func pauseAndResume() throws {
        var timer = FocusTimer()
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(90))
        try expectEqual(timer.remaining(at: start.addingTimeInterval(500)), 1_410)
        timer.start(at: start.addingTimeInterval(600))
        try expectEqual(timer.remaining(at: start.addingTimeInterval(630)), 1_380)
        try expectEqual(abs(timer.progress(at: start.addingTimeInterval(630)) - 0.08) < 0.001, true)
    }

    static func sleepAndCompletion() throws {
        var timer = FocusTimer()
        timer.start(at: start)
        let wake = start.addingTimeInterval(10_000)
        let completion = timer.tick(at: wake, configuration: configuration, autoStartBreaks: true)
        try expectEqual(completion?.duration, 1_500)
        try expectEqual(completion?.finishedAt, start.addingTimeInterval(1_500))
        try expectEqual(timer.mode, .shortBreak)
        try expectEqual(timer.remaining(at: wake), 300)
        try expectEqual(timer.completedInCycle, 1)
        try expectEqual(timer.tick(at: wake, configuration: configuration, autoStartBreaks: true), nil)
    }

    static func longBreakCycle() throws {
        var timer = FocusTimer()
        var now = start
        for index in 1...4 {
            timer.start(at: now)
            now = now.addingTimeInterval(1_500)
            try expectEqual(timer.tick(at: now, configuration: configuration)?.mode, .focus)
            try expectEqual(timer.mode, index == 4 ? .longBreak : .shortBreak)
            try expectEqual(timer.status, .ready)
            if index < 4 {
                timer.start(at: now)
                now = now.addingTimeInterval(300)
                _ = timer.tick(at: now, configuration: configuration)
            }
        }
        try expectEqual(timer.completedInCycle, 0)
        try expectEqual(timer.duration, 900)
    }

    static func skipAndReset() throws {
        var timer = FocusTimer()
        timer.start(at: start)
        timer.skip(configuration: configuration)
        try expectEqual(timer.mode, .shortBreak)
        try expectEqual(timer.completedInCycle, 0)
        timer.select(.focus, configuration: configuration)
        timer.start(at: start)
        timer.reset(configuration: configuration)
        try expectEqual(timer.tick(at: start.addingTimeInterval(2_000), configuration: configuration), nil)
        try expectEqual(timer.remaining(at: start), 1_500)
    }

    static func activeConfiguration() throws {
        var timer = FocusTimer()
        let updated = FocusConfiguration(focusMinutes: 50)
        timer.start(at: start)
        timer.reconfigure(updated)
        try expectEqual(timer.duration, 1_500)
        timer.pause(at: start.addingTimeInterval(60))
        timer.reconfigure(updated)
        try expectEqual(timer.remaining(at: start), 1_440)
        timer.reset(configuration: updated)
        try expectEqual(timer.duration, 3_000)
    }

    static func persistence() throws {
        var timer = FocusTimer()
        timer.start(at: start)
        let data = try JSONEncoder().encode(timer)
        var restored = try JSONDecoder().decode(FocusTimer.self, from: data)
        try expectEqual(restored.remaining(at: start.addingTimeInterval(100)), 1_400)
        try expectEqual(restored.tick(at: start.addingTimeInterval(1_600), configuration: configuration)?.mode, .focus)
    }

    static func autoStartAndBounds() throws {
        let configuration = FocusConfiguration(focusMinutes: -1, sessionsBeforeLongBreak: 0)
        try expectEqual(configuration.duration(for: .focus), 60)
        try expectEqual(configuration.cycleLength, 2)
        var timer = FocusTimer(configuration: configuration)
        timer.select(.shortBreak, configuration: configuration)
        timer.start(at: start)
        _ = timer.tick(at: start.addingTimeInterval(300), configuration: configuration, autoStartFocus: true)
        try expectEqual(timer.mode, .focus)
        try expectEqual(timer.status, .running)
        try expectEqual(timer.remaining(at: start.addingTimeInterval(300)), 60)
    }

    static func pausedCompletion() throws {
        var timer = FocusTimer()
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(1_499))
        try expectEqual(timer.tick(at: start.addingTimeInterval(99_999), configuration: configuration), nil)
        try expectEqual(timer.remaining(at: start.addingTimeInterval(99_999)), 1)
        try expectEqual(timer.status, .paused)
    }

    static func exactBoundary() throws {
        var timer = FocusTimer()
        timer.start(at: start)
        timer.start(at: start.addingTimeInterval(500))
        try expectEqual(timer.tick(at: start.addingTimeInterval(1_499.9), configuration: configuration), nil)
        try expectEqual(timer.tick(at: start.addingTimeInterval(1_500), configuration: configuration)?.mode, .focus)
        try expectEqual(timer.tick(at: start.addingTimeInterval(1_500), configuration: configuration), nil)
    }

    static func durationInput() throws {
        try expectEqual(SessionDuration.parse("45"), 2_700)
        try expectEqual(SessionDuration.parse(" 25:30 "), 1_530)
        try expectEqual(SessionDuration.parse("0:01"), 1)
        try expectEqual(SessionDuration.parse("180:00"), 10_800)
        for input in ["", "0", "-1", "0:00", "1:60", "180:01", "181", "1:2:3", "2.5", "25:", "abc", String(repeating: "9", count: 30)] {
            try expectEqual(SessionDuration.parse(input), nil)
        }
        try expectEqual(SessionDuration.clock(1_530), "25:30")
        try expectEqual(SessionDuration.summary(3_690), "1h 1m 30s")
    }

    static func customDuration() throws {
        var timer = FocusTimer()
        timer.start(at: start)
        try expectEqual(timer.setDuration(90), true)
        try expectEqual(timer.status, .ready)
        try expectEqual(timer.deadline, nil)
        for invalid in [0, -1, 10_801, Double.infinity, Double.nan, 1.5] {
            try expectEqual(timer.setDuration(invalid), false)
        }
        try expectEqual(timer.duration, 90)
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(20))
        timer.restart()
        try expectEqual(timer.remaining(at: start), 90)
        var restored = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
        restored.start(at: start)
        let completion = restored.tick(at: start.addingTimeInterval(90), configuration: configuration)
        try expectEqual(completion?.duration, 90)
        try expectEqual(restored.mode, .shortBreak)
        try expectEqual(restored.duration, 300)
    }

    static func activityAggregation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let records = [
            SessionRecord(finishedAt: now, duration: 1_500, intention: "One"),
            SessionRecord(finishedAt: now.addingTimeInterval(-60), duration: 1_500, intention: "Two"),
            SessionRecord(finishedAt: yesterday, duration: 30, intention: "Short")
        ]
        let activity = FocusActivity(records: records, through: now, calendar: calendar)
        let days = activity.weeks.flatMap { $0 }
        try expectEqual(activity.weeks.count, 10)
        try expectEqual(activity.weeks.allSatisfy { $0.count == 7 }, true)
        try expectEqual(days.filter(\.isInRange).count, 60)
        try expectEqual(Set(days.map(\.date)).count, 70)
        try expectEqual(activity.weeks.allSatisfy { calendar.component(.weekday, from: $0[0].date) == 1 }, true)
        try expectEqual(activity.totalSessions, 3)
        try expectEqual(activity.totalDuration, 3_030)
        try expectEqual(activity.activeDays, 2)
        try expectEqual(days.first { $0.date == calendar.startOfDay(for: now) }?.level, 2)
        try expectEqual(days.first { $0.date == calendar.startOfDay(for: yesterday) }?.level, 1)
    }

    static func activityRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let records = [firstDay.addingTimeInterval(-1), firstDay, now, now.addingTimeInterval(1)].map {
            SessionRecord(finishedAt: $0, duration: 60, intention: "Boundary")
        }
        let activity = FocusActivity(records: records, through: now, calendar: calendar)
        try expectEqual(activity.startDate, firstDay)
        try expectEqual(activity.totalSessions, 2)
        try expectEqual(activity.totalDuration, 120)
        try expectEqual(activity.activeDays, 2)
        let empty = FocusActivity(records: [], through: now, calendar: calendar)
        try expectEqual(empty.totalSessions, 0)
        try expectEqual(empty.weeks.flatMap { $0 }.allSatisfy { $0.level == 0 }, true)
        let leapYear = FocusActivity(records: [], through: ISO8601DateFormatter().date(from: "2024-03-31T12:00:00Z")!, calendar: calendar)
        try expectEqual(leapYear.startDate, calendar.date(from: DateComponents(year: 2024, month: 2, day: 1))!)
        try expectEqual(leapYear.weeks.flatMap { $0 }.filter(\.isInRange).count, 60)
        let newYear = FocusActivity(records: [], through: ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!, calendar: calendar)
        try expectEqual(newYear.startDate, calendar.date(from: DateComponents(year: 2025, month: 11, day: 17))!)
        try expectEqual(newYear.weeks.flatMap { $0 }.filter(\.isInRange).count, 60)
    }

    static func activityTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-03-09T16:00:00Z")!
        let records = ["2026-03-08T04:59:00Z", "2026-03-08T05:01:00Z", "2026-03-08T07:01:00Z"].map {
            SessionRecord(finishedAt: formatter.date(from: $0)!, duration: 1_500, intention: "Local day")
        }
        let activity = FocusActivity(records: records, through: now, calendar: calendar)
        let days = activity.weeks.flatMap { $0 }
        try expectEqual(activity.activeDays, 2)
        try expectEqual(activity.totalDuration, 4_500)
        let march8 = calendar.startOfDay(for: formatter.date(from: "2026-03-08T16:00:00Z")!)
        try expectEqual(days.first { $0.date == march8 }?.sessions, 2)
        try expectEqual(days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 }, true)
    }

    static func preferenceMigration() throws {
        let legacy = Data("""
        {"timer":{"focusMinutes":47,"shortBreakMinutes":7,"longBreakMinutes":22,"sessionsBeforeLongBreak":3},
         "autoStartBreaks":true,"startMusicWithFocus":false,"notifications":true}
        """.utf8)
        var preferences = try JSONDecoder().decode(Preferences.self, from: legacy)
        try expectEqual(preferences.appearance, .candlelight)
        try expectEqual(preferences.timer.focusMinutes, 47)
        try expectEqual(preferences.autoStartBreaks, true)
        try expectEqual(preferences.startMusicWithFocus, false)
        try expectEqual(preferences.notifications, true)
        preferences.appearance = .catppuccin
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        try expectEqual(restored.appearance, .catppuccin)
        try expectEqual(restored.timer.focusMinutes, 47)
        var previousTheme = try JSONSerialization.jsonObject(with: legacy) as! [String: Any]
        previousTheme["appearance"] = "tokyoNight"
        let migrated = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: previousTheme))
        try expectEqual(migrated.appearance, .candlelight)
        try expectEqual(migrated.timer.focusMinutes, 47)
        try expectEqual(migrated.notifications, true)
    }
}
