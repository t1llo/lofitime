import Foundation

public struct RoomAddition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let minutes: Double

    public static let all: [RoomAddition] = [
        .init(id: "leaves", title: "Leafy little plants", minutes: 15),
        .init(id: "desk-lamp", title: "A warm desk lamp", minutes: 45),
        .init(id: "rug", title: "A soft woven rug", minutes: 90),
        .init(id: "bookshelf", title: "A shelf for your books", minutes: 180),
        .init(id: "floor-lamp", title: "Floor lamp and pillows", minutes: 300),
        .init(id: "hanging-plants", title: "Trailing window plants", minutes: 420),
        .init(id: "blossoms", title: "Flowers in full bloom", minutes: 540),
        .init(id: "fairy-lights", title: "A canopy of fairy lights", minutes: 720)
    ]
}

/// One room, independent of calendar pages. A session nourishes it fully for three days,
/// then gently fades over four more days. Nothing about the saved history is changed.
public struct FocusRoom: Sendable {
    public let recentDuration: TimeInterval
    public let nourishment: TimeInterval
    public var minutes: Double { nourishment / 60 }
    public var nextAddition: RoomAddition? { RoomAddition.all.first { minutes < $0.minutes } }
    public var additions: [RoomAddition] { RoomAddition.all.filter { minutes >= $0.minutes } }
    public var progressToNext: Double {
        guard let next = nextAddition else { return 1 }
        let previous = additions.last?.minutes ?? 0
        return min(1, max(0, (minutes - previous) / (next.minutes - previous)))
    }
    public var bookCount: Int { minutes < 180 ? 0 : min(24, 1 + Int(min(600, minutes - 180) / 25)) }
    public var plantGrowth: Double { min(1, minutes / 540) }
    /// Avoid rebuilding hundreds of scene nodes on every countdown tick.
    public var visualStep: Int { nourishment > 0 ? max(1, Int(min(780, minutes))) : 0 }
    public var title: String {
        switch minutes {
        case ...0: "A quiet beginning"
        case ..<45: "A little life"
        case ..<180: "A warm little corner"
        case ..<420: "Feeling like home"
        case ..<720: "Room to bloom"
        default: "Your cozy hideaway"
        }
    }

    public init(records: [SessionRecord], through now: Date) {
        var recent: TimeInterval = 0
        var nourishment: TimeInterval = 0
        for record in records where record.duration.isFinite && record.duration > 0 {
            let age = now.timeIntervalSince(record.finishedAt) / 86_400
            guard age >= 0, age < 7 else { continue }
            recent += record.duration
            nourishment += record.duration * min(1, (7 - age) / 4)
        }
        self.recentDuration = recent
        self.nourishment = nourishment
    }
}
