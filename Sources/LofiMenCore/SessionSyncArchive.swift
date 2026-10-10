import Foundation

/// Completed sessions are immutable. Merging is an append-only union by session ID.
public struct SessionSyncArchive: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public let records: [SessionRecord]

    public init(records: [SessionRecord]) throws {
        format = "lofitime.sessions"
        version = 1
        self.records = try Self.merge(records, [])
    }

    public static func decode(_ data: Data) throws -> Self {
        let archive: Self
        do { archive = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw SessionSyncError.invalidArchive }
        guard archive.format == "lofitime.sessions" else { throw SessionSyncError.invalidArchive }
        guard archive.version == 1 else { throw SessionSyncError.unsupportedVersion }
        return try Self(records: archive.records)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // The native Date encoding preserves the original sub-second precision and IDs.
        return try encoder.encode(self)
    }

    public static func merge(_ local: [SessionRecord], _ remote: [SessionRecord]) throws -> [SessionRecord] {
        var sessions: [UUID: SessionRecord] = [:]
        for record in local + remote {
            // A focus timer currently tops out at three hours. Reject implausible imported
            // durations before they can overflow the activity UI's integer summaries.
            guard record.duration.isFinite, record.duration > 0, record.duration <= 86_400,
                  record.finishedAt.timeIntervalSince1970.isFinite,
                  (0...253_402_300_799).contains(record.finishedAt.timeIntervalSince1970) else {
                throw SessionSyncError.invalidArchive
            }
            if let existing = sessions[record.id], existing != record {
                throw SessionSyncError.conflictingSession
            }
            sessions[record.id] = record
        }
        return sessions.values.sorted {
            if $0.finishedAt != $1.finishedAt { return $0.finishedAt > $1.finishedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

public enum SessionSyncError: LocalizedError {
    case invalidArchive, unsupportedVersion, conflictingSession

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "The repository has an invalid Lofitime sync file. Your local history is safe."
        case .unsupportedVersion: "This history uses a newer sync format. Update Lofitime on this Mac to sync it."
        case .conflictingSession: "The history contains conflicting copies of a session. Your local history is safe."
        }
    }
}
