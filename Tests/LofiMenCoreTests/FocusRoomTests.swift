import Foundation
import LofiMenCore

extension FocusTimerTests {
    static func roomGrowth() throws {
        let sessions = (0..<4).map { index in
            SessionRecord(finishedAt: start.addingTimeInterval(-Double(index) * 86_400), duration: 1_500, intention: "Study")
        }
        let room = FocusRoom(records: sessions, through: start)
        try expectEqual(room.recentDuration, 6_000)
        try expectEqual(room.nourishment, 6_000)
        try expectEqual(room.additions.map(\.id), ["leaves", "desk-lamp", "rug"])
        // Splitting the same focus across days doesn't reset the room or change its rewards.
        let combined = [SessionRecord(finishedAt: start, duration: 6_000, intention: "Study")]
        try expectEqual(FocusRoom(records: combined, through: start).visualStep, room.visualStep)
        let afterThreeDays = FocusRoom(records: combined, through: start.addingTimeInterval(3 * 86_400))
        let afterFiveDays = FocusRoom(records: combined, through: start.addingTimeInterval(5 * 86_400))
        let afterOneWeek = FocusRoom(records: combined, through: start.addingTimeInterval(7 * 86_400))
        try expectEqual(afterThreeDays.nourishment, 6_000)
        try expectEqual(afterFiveDays.nourishment, 3_000)
        try expectEqual(afterFiveDays.recentDuration, 6_000)
        try expectEqual(afterOneWeek.nourishment, 0)
        try expectEqual(afterOneWeek.recentDuration, 0)
        try expectEqual(afterOneWeek.additions.isEmpty, true)
        try expectEqual(afterOneWeek.bookCount, 0)
        try expectEqual(afterOneWeek.visualStep, 0)
        let justBefore = FocusRoom(records: combined, through: start.addingTimeInterval(7 * 86_400 - 1))
        try expectEqual(justBefore.nourishment > 0 && justBefore.nourishment < 1, true)
        // New focus revives the room immediately, without rewriting old records.
        let returned = sessions + [SessionRecord(finishedAt: start.addingTimeInterval(8 * 86_400), duration: 1_500, intention: "Back")]
        try expectEqual(FocusRoom(records: returned, through: start.addingTimeInterval(8 * 86_400)).nourishment, 1_500)
    }

    static func roomHistory() throws {
        var previousBooks = 0
        var previousGrowth = 0.0
        for minutes in stride(from: 0, through: 3_000, by: 5) {
            let records = [SessionRecord(finishedAt: start, duration: Double(minutes) * 60, intention: "Focus")]
            let room = FocusRoom(records: records, through: start)
            try expectEqual(room.bookCount >= previousBooks && room.bookCount <= 24, true)
            try expectEqual(room.plantGrowth >= previousGrowth && room.plantGrowth <= 1, true)
            try expectEqual((0...1).contains(room.progressToNext), true)
            try expectEqual(room.visualStep <= 780, true)
            previousBooks = room.bookCount
            previousGrowth = room.plantGrowth
        }
        let records = [SessionRecord(finishedAt: start, duration: 43_200, intention: "A cozy room")]
        let before = FocusRoom(records: records, through: start)
        let after = FocusRoom(records: [SessionRecord(finishedAt: start, duration: 46_800, intention: "More books")], through: start)
        try expectEqual(after.bookCount > before.bookCount && after.visualStep > before.visualStep, true)
        try expectEqual(after.bookCount, 24)
        let now = start.addingTimeInterval(8 * 86_400)
        let stats = FocusActivity(records: records, through: now)
        try expectEqual(FocusRoom(records: records, through: now).additions.isEmpty, true)
        try expectEqual(stats.allTimeDuration, 43_200)
        let older = FocusActivity(records: records, through: now, weekOffset: -1, monthOffset: -1)
        try expectEqual(older.allTimeDuration, 43_200)
        try expectEqual(FocusRoom(records: records, through: start).nextAddition == nil, true)
    }
}
