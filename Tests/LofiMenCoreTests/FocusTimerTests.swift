import Foundation
import LofiMenCore

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, line: UInt = #line) throws {
    guard actual == expected else {
        throw TestFailure(description: "Line \(line): expected \(expected), got \(actual)")
    }
}

@main
struct FocusTimerTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let configuration = FocusConfiguration()

    @MainActor static func main() async {
        let tests: [(String, @MainActor () async throws -> Void)] = [
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
            ("Weekly totals respect local week starts and future days", activityAggregation),
            ("Monthly history has exact boundaries, leap days and calendar averages", activityHistory),
            ("Room grows across sessions and gently empties after a quiet week", roomGrowth),
            ("Room progression is bounded and calendar browsing keeps history", roomHistory),
            ("Invalid and future records cannot inflate activity or grow the room", invalidActivity),
            ("Activity respects local days across daylight-saving changes", activityTimeZone),
            ("Headphone loss pauses Bluetooth, USB, and same-device jack routes", headphoneDisconnection),
            ("Existing preferences migrate and theme choice persists", preferenceMigration),
            ("Sync merges immutable session IDs without duplicating focus time", syncArchiveMerge),
            ("Sync rejects conflicting, corrupt, and newer archives", syncArchiveValidation),
            ("Two Macs create one private repository and merge concurrent updates", syncTwoComputers),
            ("Sync stops for public, replaced, unrelated, and inaccessible repositories", syncRepositoryChecks),
            ("Create and connect are distinct, repository links support writable shared sync", syncRepositoryLinks),
            ("Large sync histories use an exact-revision blob download", syncLargeHistory),
            ("In-flight sync preserves new local sessions and catches up immediately", syncInFlightSession),
            ("Offline sessions retry and saved connections sync on launch", syncOfflineAndRelaunch),
            ("Disconnect cancels sync and ignores late responses", syncDisconnect),
            ("GitHub CLI handles large stdin/stdout, errors, timeout, and cancellation", syncCLI)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try await test()
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
        let days = activity.week.days
        try expectEqual(days.count, 7)
        try expectEqual(days.filter(\.isInRange).count, 3)
        try expectEqual(Set(days.map(\.date)).count, 7)
        try expectEqual(calendar.component(.weekday, from: days[0].date), calendar.firstWeekday)
        try expectEqual(activity.week.totalSessions, 3)
        try expectEqual(activity.week.totalDuration, 3_030)
        try expectEqual(activity.week.activeDays, 2)
        try expectEqual(days.first { $0.date == calendar.startOfDay(for: now) }?.duration, 3_000)
        try expectEqual(days.first { $0.date == calendar.startOfDay(for: yesterday) }?.duration, 30)
        calendar.firstWeekday = 2
        let mondayFirst = FocusActivity(records: records, through: now, calendar: calendar)
        try expectEqual(calendar.component(.weekday, from: mondayFirst.week.startDate), 2)
        try expectEqual(mondayFirst.week.days.filter(\.isInRange).count, 2)
        try expectEqual(mondayFirst.week.totalDuration, 3_030)
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
        let days = activity.month.days
        try expectEqual(activity.month.activeDays, 2)
        try expectEqual(activity.month.totalDuration, 4_500)
        let march8 = calendar.startOfDay(for: formatter.date(from: "2026-03-08T16:00:00Z")!)
        try expectEqual(days.first { $0.date == march8 }?.sessions, 2)
        try expectEqual(days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 }, true)
    }

    static func activityHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = ISO8601DateFormatter().date(from: "2024-03-12T16:00:00Z")!
        let current = FocusActivity(records: [], through: now, calendar: calendar)
        let records = [current.month.startDate.addingTimeInterval(-1), current.month.startDate, now].map {
            SessionRecord(finishedAt: $0, duration: 1_500, intention: "Boundary")
        }
        let history = FocusActivity(records: records, through: now, calendar: calendar, monthOffset: -1)
        let live = FocusActivity(records: records, through: now, calendar: calendar)
        try expectEqual(history.month.totalSessions, 1)
        try expectEqual(history.month.days.count, 29)
        try expectEqual(history.month.dailyAverage, 1_500 / 29)
        try expectEqual(live.month.totalSessions, 2)
        try expectEqual(live.month.dailyAverage, 250)
        try expectEqual(history.month.endDate, live.month.startDate)
        try expectEqual(Set(history.month.days.map(\.date)).isDisjoint(with: live.month.days.map(\.date)), true)
        try expectEqual(history.allTimeDuration, live.allTimeDuration)
        try expectEqual(live.canGoToPreviousMonth, true)
        try expectEqual(history.canGoToPreviousMonth, false)
        let older = FocusActivity(records: records, through: now, calendar: calendar, monthOffset: -2)
        try expectEqual(older.month.totalSessions, 0)
        let clamped = FocusActivity(records: records, through: now, calendar: calendar, weekOffset: 3, monthOffset: 3)
        try expectEqual(clamped.month.startDate, live.month.startDate)
        try expectEqual(clamped.week.startDate, live.week.startDate)
        let previousWeek = FocusActivity(records: records, through: now, calendar: calendar, weekOffset: -1)
        try expectEqual(previousWeek.week.endDate, live.week.startDate)
        let january = ISO8601DateFormatter().date(from: "2026-01-31T16:00:00Z")!
        let december = FocusActivity(records: [], through: january, calendar: calendar, monthOffset: -1)
        try expectEqual(calendar.component(.year, from: december.month.startDate), 2025)
        try expectEqual(calendar.component(.month, from: december.month.startDate), 12)
        try expectEqual(december.month.days.count, 31)
    }

    static func invalidActivity() throws {
        var records = [0, -30, .infinity, .nan, 60].map {
            SessionRecord(finishedAt: start, duration: $0, intention: "Imported record")
        }
        records.append(SessionRecord(finishedAt: start.addingTimeInterval(1), duration: 1_500, intention: "Future"))
        let activity = FocusActivity(records: records, through: start)
        try expectEqual(activity.week.totalDuration, 60)
        try expectEqual(activity.month.totalSessions, 1)
        try expectEqual(activity.month.activeDays, 1)
        try expectEqual(activity.allTimeDuration, 60)
        try expectEqual(FocusRoom(records: records, through: start).nourishment, 60)
        for duration in [Double.nan, .infinity, -1] {
            let day = ActivityDay(date: start, duration: duration, sessions: 0, isInRange: true)
            try expectEqual(day.duration, 0)
        }
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
        for appearance in AppAppearance.allCases {
            preferences.appearance = appearance
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
            try expectEqual(restored.appearance, appearance)
            try expectEqual(restored.timer.focusMinutes, 47)
        }
        var unknownTheme = try JSONSerialization.jsonObject(with: legacy) as! [String: Any]
        unknownTheme["appearance"] = "unknownTheme"
        let migrated = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: unknownTheme))
        try expectEqual(migrated.appearance, .candlelight)
        try expectEqual(migrated.timer.focusMinutes, 47)
        try expectEqual(migrated.notifications, true)
    }

    static func headphoneDisconnection() throws {
        let speakers = AudioOutputRoute(deviceID: 1, isHeadphones: false)
        let bluetooth = AudioOutputRoute(deviceID: 2, isHeadphones: true)
        let usb = AudioOutputRoute(deviceID: 3, isHeadphones: true)
        let wired = AudioOutputRoute(deviceID: 1, isHeadphones: true, dataSource: 10, jackConnected: true)
        let unplugged = AudioOutputRoute(deviceID: 1, isHeadphones: false, dataSource: 11, jackConnected: false)
        try expectEqual(bluetooth.shouldPause(afterChangingTo: speakers), true)
        try expectEqual(usb.shouldPause(afterChangingTo: speakers), true)
        try expectEqual(wired.shouldPause(afterChangingTo: unplugged), true)
        try expectEqual(bluetooth.shouldPause(afterChangingTo: nil), true)
        try expectEqual(bluetooth.shouldPause(afterChangingTo: AudioOutputRoute(deviceID: 2, isHeadphones: true, isConnected: false)), true)
        // Some jacks retain their headphone terminal type after the plug is removed.
        try expectEqual(wired.shouldPause(afterChangingTo: AudioOutputRoute(deviceID: 1, isHeadphones: true, dataSource: 10, jackConnected: false)), true)
        try expectEqual(wired.shouldPause(afterChangingTo: AudioOutputRoute(deviceID: 1, isHeadphones: true, dataSource: 11, jackConnected: true)), true)
        for route in [speakers, bluetooth, usb, wired] {
            try expectEqual(route.shouldPause(afterChangingTo: route), false)
        }
        // Connecting headphones and unrelated device notifications must not interrupt music.
        try expectEqual(speakers.shouldPause(afterChangingTo: bluetooth), false)
        try expectEqual(speakers.shouldPause(afterChangingTo: wired), false)
        try expectEqual(speakers.shouldPause(afterChangingTo: nil), false)
        let alreadyDisconnected = AudioOutputRoute(deviceID: 2, isHeadphones: true, isConnected: false)
        try expectEqual(alreadyDisconnected.shouldPause(afterChangingTo: speakers), false)
    }
}
