import Foundation

public struct SessionRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let finishedAt: Date
    public let duration: TimeInterval
    public let intention: String

    public init(id: UUID = UUID(), finishedAt: Date, duration: TimeInterval, intention: String) {
        self.id = id
        self.finishedAt = finishedAt
        self.duration = duration
        self.intention = intention
    }

    public var minutes: Int { Int(duration / 60) }
}
