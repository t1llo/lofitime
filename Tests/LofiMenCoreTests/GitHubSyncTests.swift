import Foundation
import LofiMenCore
import LofiMenSync

extension FocusTimerTests {
    static func syncArchiveMerge() throws {
        let shared = SessionRecord(finishedAt: start.addingTimeInterval(0.1234567), duration: 1_500, intention: "Shared ☕️")
        let first = SessionRecord(finishedAt: start, duration: 600, intention: "First Mac")
        let second = SessionRecord(finishedAt: start, duration: 900, intention: "Second Mac")
        let merged = try SessionSyncArchive.merge([shared, first], [second, shared])
        try expectEqual(merged.count, 3)
        try expectEqual(try SessionSyncArchive.merge([second, shared], [first, shared]), merged)
        try expectEqual(try SessionSyncArchive.merge(merged, merged), merged)
        let archive = try SessionSyncArchive(records: merged)
        try expectEqual(try SessionSyncArchive.decode(archive.encoded()), archive)
        try expectEqual(try SessionSyncArchive(records: merged.reversed()).encoded(), archive.encoded())
        let activity = FocusActivity(records: merged, through: start.addingTimeInterval(1))
        try expectEqual(activity.allTimeDuration, 3_000)
        try expectEqual(activity.month.totalSessions, 3)
        try expectEqual(FocusRoom(records: merged, through: start.addingTimeInterval(1)).recentDuration, 3_000)
    }

    static func syncArchiveValidation() throws {
        let record = SessionRecord(finishedAt: start, duration: 1_500, intention: "Original")
        let changed = SessionRecord(id: record.id, finishedAt: start, duration: 3_000, intention: "Changed")
        try expectSyncFailure { _ = try SessionSyncArchive.merge([record], [changed]) }
        for duration in [0, -1, Double.infinity, .nan, 86_401, .greatestFiniteMagnitude] {
            try expectSyncFailure { _ = try SessionSyncArchive(records: [SessionRecord(finishedAt: start, duration: duration, intention: "Invalid")]) }
        }
        let archive = try SessionSyncArchive(records: [record]).encoded()
        var object = try JSONSerialization.jsonObject(with: archive) as! [String: Any]
        object["version"] = 2
        try expectSyncFailure { _ = try SessionSyncArchive.decode(JSONSerialization.data(withJSONObject: object)) }
        object["version"] = 1
        object["format"] = "another.app"
        try expectSyncFailure { _ = try SessionSyncArchive.decode(JSONSerialization.data(withJSONObject: object)) }
        try expectSyncFailure { _ = try SessionSyncArchive.decode(Data("not JSON".utf8)) }
    }

    static func syncTwoComputers() async throws {
        let api = MemoryGitHub()
        let first = GitHubSyncClient(api: api)
        let second = GitHubSyncClient(api: api)
        let shared = SessionRecord(finishedAt: start, duration: 1_500, intention: "Already on both Macs")
        // Another Mac creates the repository and initializes its sync file between setup requests.
        await api.update { $0.createRace = true; $0.archiveOnRoot = [shared] }
        try await expectSyncFailure { _ = try await first.create(name: "lofitime-sync") }
        let a = try await first.connect(repository: "https://github.com/test-user/lofitime-sync")
        let b = try await second.connect(repository: a.repository)
        try expectEqual(a, b)
        try expectEqual(await api.creations, 1)
        let local = SessionRecord(finishedAt: start.addingTimeInterval(60), duration: 600, intention: "Offline on second Mac")
        let racing = SessionRecord(finishedAt: start.addingTimeInterval(120), duration: 900, intention: "First Mac finishes during upload")
        _ = try await first.synchronize(a, records: [shared])
        await api.update { $0.racingSession = racing }
        let merged = try await second.synchronize(b, records: [shared, local])
        try expectEqual(Set(merged.map(\.id)), Set([shared.id, local.id, racing.id]))
        try expectEqual(try await api.savedRecords(), merged)
        let writes = await api.uploads
        try expectEqual(try await first.synchronize(a, records: [shared]), merged)
        try expectEqual(await api.uploads, writes)
        try expectEqual(await api.conflicts, 1)
    }

    static func syncRepositoryChecks() async throws {
        let api = MemoryGitHub()
        let client = GitHubSyncClient(api: api)
        for name in ["", "../private", "owner/repo", "--help", "a?b", "foo\n", String(repeating: "a", count: 101)] {
            try await expectSyncFailure { _ = try await client.create(name: name) }
        }
        try expectEqual(await api.requests, 0)
        let connection = try await client.create(name: "lofitime-sync")
        let session = SessionRecord(finishedAt: start, duration: 60, intention: "Stays local")
        await api.update { $0.isPrivate = false }
        try await expectSyncFailure { _ = try await client.synchronize(connection, records: [session]) }
        try await expectSyncFailure { _ = try await client.connect(repository: connection.repository) }
        await api.update { $0.isPrivate = true; $0.repositoryID = 999 }
        try await expectSyncFailure { _ = try await client.synchronize(connection, records: [session]) }
        await api.update { $0.repositoryID = 42; $0.account = "someone-else" }
        try await expectSyncFailure { _ = try await client.synchronize(connection, records: [session]) }
        await api.update { $0.account = "test-user"; $0.unrelatedFiles = true }
        try await expectSyncFailure { _ = try await client.connect(repository: connection.repository) }
        await api.update { $0.unrelatedFiles = false; $0.readStatus = 403 }
        try await expectSyncFailure { _ = try await client.synchronize(connection, records: [session]) }
        await api.update { $0.readStatus = nil; $0.invalidArchive = true }
        try await expectSyncFailure { _ = try await client.synchronize(connection, records: [session]) }
        try expectEqual(await api.uploads, 0)
    }

    static func syncLargeHistory() async throws {
        let api = MemoryGitHub()
        await api.update { $0.branch = "sync+history" }
        let client = GitHubSyncClient(api: api)
        let connection = try await client.create(name: "lofitime-sync")
        let record = SessionRecord(finishedAt: start, duration: 1_500, intention: String(repeating: "A", count: 1_100_000))
        _ = try await client.synchronize(connection, records: [record])
        try expectEqual(try await client.synchronize(connection, records: []), [record])
        try expectEqual(await api.blobReads, 1)
    }

    @MainActor static func syncInFlightSession() async throws {
        let api = MemoryGitHub()
        let gate = SyncGate()
        await api.update { $0.uploadGate = gate }
        let suite = "com.lofimen.sync-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = GitHubSyncService(defaults: defaults, client: GitHubSyncClient(api: api))
        defer { service.disconnect() }
        let first = SessionRecord(finishedAt: start, duration: 60, intention: "Before upload")
        let second = SessionRecord(finishedAt: start.addingTimeInterval(60), duration: 120, intention: "During upload")
        var records = [first]
        service.start(snapshot: { records }, receive: { records = $0 })
        try expectEqual(service.isEnabled, false)
        try expectEqual(await api.requests, 0)
        service.create()
        try await waitForSync { await gate.entered }
        records.append(second)
        service.syncNow()
        await gate.release()
        try await waitForSync { !service.isBusy }
        try expectEqual(service.error, nil)
        try expectEqual(Set(records.map(\.id)), Set([first.id, second.id]))
        try expectEqual(try await api.savedRecords(), records)
        try expectEqual(await api.uploads, 2)
        try expectEqual(service.lastSyncedAt != nil, true)
    }

    @MainActor static func syncOfflineAndRelaunch() async throws {
        let api = MemoryGitHub()
        let suite = "com.lofimen.sync-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = GitHubSyncClient(api: api)
        var records = [SessionRecord(finishedAt: start, duration: 60, intention: "First session")]
        var service: GitHubSyncService? = GitHubSyncService(defaults: defaults, client: client)
        service!.start(snapshot: { records }, receive: { records = $0 })
        service!.create()
        try await waitForSync { service?.isBusy == false }
        try expectEqual(service?.error, nil)
        let firstSync = service!.lastSyncedAt
        await api.update { $0.offline = true }
        records.append(SessionRecord(finishedAt: start.addingTimeInterval(60), duration: 120, intention: "Offline work"))
        let offlineRecords = records
        service!.syncNow()
        try await waitForSync { service?.isBusy == false }
        try expectEqual(service?.error != nil, true)
        try expectEqual(service?.lastSyncedAt, firstSync)
        try expectEqual(records, offlineRecords)
        // Simulate quitting and reopening with persisted local history and sync configuration.
        service = nil
        await api.update { $0.offline = false }
        let relaunched = GitHubSyncService(defaults: defaults, client: client)
        defer { relaunched.disconnect() }
        relaunched.start(snapshot: { records }, receive: { records = $0 })
        try await waitForSync { !relaunched.isBusy }
        try expectEqual(relaunched.isEnabled, true)
        try expectEqual(relaunched.error, nil)
        try expectEqual(try await api.savedRecords(), records)
        try expectEqual(records.count, 2)
        let requests = await api.requests
        relaunched.refreshIfNeeded()
        relaunched.refreshIfNeeded()
        try expectEqual(await api.requests, requests)
    }

    @MainActor static func syncDisconnect() async throws {
        let api = MemoryGitHub()
        let gate = SyncGate()
        await api.update { $0.uploadGate = gate }
        let suite = "com.lofimen.sync-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = GitHubSyncService(defaults: defaults, client: GitHubSyncClient(api: api))
        var deliveries = 0
        service.start(snapshot: { [] }, receive: { _ in deliveries += 1 })
        service.create()
        try await waitForSync { await gate.entered }
        service.disconnect()
        await gate.release()
        try await waitForSync { await api.finishedUploads == 1 }
        await Task.yield()
        try expectEqual(service.isEnabled, false)
        try expectEqual(service.isBusy, false)
        try expectEqual(service.lastSyncedAt, nil)
        try expectEqual(deliveries, 0)
        try expectEqual(defaults.data(forKey: "sync.github.connection.v1"), nil)
        service.syncNow()
        try expectEqual(service.isBusy, false)
    }

    static func syncCLI() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lofitime-fake-gh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("gh")
        let script = """
        #!/bin/sh
        case "$*" in
          *slow*) exec /bin/sleep 30 ;;
          *unauthorized*) printf 'HTTP/2.0 401 Unauthorized\\r\\nContent-Type: application/json\\r\\n\\r\\n{}'; exit 1 ;;
          *signin*) printf 'Run gh auth login' >&2; exit 1 ;;
          *) printf 'HTTP/2.0 200 OK\\r\\nContent-Type: application/json\\r\\n\\r\\n'; /bin/cat ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let cli = GitHubCLI(executable: executable, timeout: 2)
        let body = Data(String(repeating: "large history\n", count: 20_000).utf8)
        let response = try await cli.request("PUT", endpoint: "echo", body: body)
        try expectEqual(response.status, 200)
        try expectEqual(response.body, body)
        try expectEqual(try await cli.request("GET", endpoint: "unauthorized", body: nil).status, 401)
        try await expectSyncFailure { _ = try await cli.request("GET", endpoint: "signin", body: nil) }
        let fastTimeout = GitHubCLI(executable: executable, timeout: 0.05)
        do {
            _ = try await fastTimeout.request("GET", endpoint: "slow", body: nil)
            throw TestFailure(description: "A hung gh process did not time out")
        } catch GitHubSyncError.timedOut { }
        let task = Task { try await cli.request("GET", endpoint: "slow", body: nil) }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        do {
            _ = try await task.value
            throw TestFailure(description: "A cancelled gh process returned success")
        } catch is CancellationError { }
    }

    static func syncRepositoryLinks() async throws {
        for input in ["https://github.com/test-user/lofitime-sync", "https://github.com/test-user/lofitime-sync.git/",
                      "test-user/lofitime-sync", "git@github.com:test-user/lofitime-sync.git", "  https://github.com/test-user/lofitime-sync  "] {
            try expectEqual(try GitHubSyncClient.repository(from: input), "test-user/lofitime-sync")
        }
        for input in ["", "lofitime-sync", "https://example.com/test-user/lofitime-sync", "http://github.com/a/b",
                      "https://github.com/a/b/tree/main", "https://github.com/a/b?token=secret", "https://user@github.com/a/b",
                      "../history", "https://github.com/a/b#readme", "https://github.com:99/a/b", "a/b\nc"] {
            try expectSyncFailure { _ = try GitHubSyncClient.repository(from: input) }
        }
        let api = MemoryGitHub()
        let client = GitHubSyncClient(api: api)
        try await expectSyncFailure { _ = try await client.connect(repository: "test-user/lofitime-sync") }
        try expectEqual(await api.creations, 0)
        _ = try await client.create(name: "lofitime-sync")
        try await expectSyncFailure { _ = try await client.create(name: "lofitime-sync") }
        try expectEqual(await api.creations, 1)
        // A different account with write access can subscribe to the shared private repository.
        await api.update { $0.account = "collaborator" }
        let connection = try await client.connect(repository: "https://github.com/test-user/lofitime-sync")
        try expectEqual(connection.account, "collaborator")
        _ = try await client.synchronize(connection, records: [])
        await api.update { $0.canWrite = false }
        try await expectSyncFailure { _ = try await client.connect(repository: connection.repository) }
        try expectEqual(await api.creations, 1)
    }
}

private func expectSyncFailure(_ operation: () throws -> Void) throws {
    do { try operation() }
    catch is GitHubSyncError { return }
    catch is SessionSyncError { return }
    throw TestFailure(description: "Expected a sync error")
}

private func expectSyncFailure(_ operation: () async throws -> Void) async throws {
    do { try await operation() }
    catch is GitHubSyncError { return }
    catch is SessionSyncError { return }
    throw TestFailure(description: "Expected a sync error")
}

@MainActor private func waitForSync(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw TestFailure(description: "Sync did not finish") }
        await Task.yield()
    }
}

private actor SyncGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

/// An in-memory GitHub Contents API with SHA compare-and-swap, shared by both simulated Macs.
private actor MemoryGitHub: GitHubAPI {
    struct Options: Sendable {
        var account = "test-user"
        var repositoryID: Int64 = 42
        var isPrivate = true
        var canWrite = true
        var offline = false
        var unrelatedFiles = false
        var invalidArchive = false
        var createRace = false
        var archiveOnRoot: [SessionRecord]?
        var branch = "main"
        var readStatus: Int?
        var racingSession: SessionRecord?
        var uploadGate: SyncGate?
    }
    private var options = Options()
    private var exists = false
    private var archive: Data?
    private var revision = 0
    private(set) var requests = 0
    private(set) var creations = 0
    private(set) var uploads = 0
    private(set) var finishedUploads = 0
    private(set) var conflicts = 0
    private(set) var blobReads = 0
    private var sha: String { String(format: "%040x", revision) }

    func update(_ change: @Sendable (inout Options) -> Void) { change(&options) }
    func savedRecords() throws -> [SessionRecord] { try SessionSyncArchive.decode(archive ?? Data()).records }

    func request(_ method: String, endpoint: String, body: Data?) async throws -> GitHubResponse {
        requests += 1
        if options.offline { throw GitHubSyncError.unavailable }
        if endpoint == "user" { return try response(["login": options.account]) }
        if endpoint == "user/repos" {
            let data = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
            try expectEqual(data["private"] as? Bool, true)
            if exists { return GitHubResponse(status: 422, body: Data()) }
            exists = true
            creations += 1
            if options.createRace {
                options.createRace = false
                return GitHubResponse(status: 422, body: Data())
            }
            return try repositoryResponse()
        }
        if endpoint == "repos/test-user/lofitime-sync" {
            return exists ? try repositoryResponse() : GitHubResponse(status: 404, body: Data())
        }
        if endpoint == "repos/test-user/lofitime-sync/contents" {
            if let records = options.archiveOnRoot {
                options.archiveOnRoot = nil
                archive = try SessionSyncArchive(records: records).encoded()
                revision += 1
                return try response([["name": GitHubSyncClient.fileName]])
            }
            return try response(options.unrelatedFiles ? [["name": "existing-project.txt"]] : [])
        }
        if endpoint.contains("/git/blobs/") {
            try expectEqual(endpoint.hasSuffix(sha), true)
            blobReads += 1
            return try response(["encoding": "base64", "content": archive!.base64EncodedString()])
        }
        guard endpoint.contains("/contents/lofitime-sessions.json") else {
            throw TestFailure(description: "Unexpected GitHub API endpoint: \(endpoint)")
        }
        if method == "GET" {
            if options.branch.contains("+") { try expectEqual(endpoint.contains("%2B"), true) }
            if let status = options.readStatus { return GitHubResponse(status: status, body: Data()) }
            let data = options.invalidArchive ? Data("{\"format\":\"other-app\"}".utf8) : archive
            guard let data else { return GitHubResponse(status: 404, body: Data()) }
            return try response(["type": "file", "sha": sha, "size": data.count,
                                 "encoding": data.count > 1_048_576 ? "none" : "base64",
                                 "content": data.count > 1_048_576 ? "" : data.base64EncodedString()])
        }
        try expectEqual(method, "PUT")
        if let gate = options.uploadGate {
            options.uploadGate = nil
            await gate.wait()
        }
        defer { finishedUploads += 1 }
        let update = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
        try expectEqual(update["branch"] as? String, options.branch)
        if let session = options.racingSession {
            options.racingSession = nil
            archive = try SessionSyncArchive(records: (try savedRecords()) + [session]).encoded()
            revision += 1
        }
        guard update["sha"] as? String == (archive == nil ? nil : sha) else {
            conflicts += 1
            return GitHubResponse(status: 409, body: Data())
        }
        archive = Data(base64Encoded: update["content"] as! String)!
        _ = try SessionSyncArchive.decode(archive!)
        revision += 1
        uploads += 1
        return try response(["ok": true], status: 201)
    }

    private func repositoryResponse() throws -> GitHubResponse {
        try response(["id": options.repositoryID, "full_name": "test-user/lofitime-sync", "private": options.isPrivate,
                      "archived": false, "default_branch": options.branch, "permissions": ["push": options.canWrite]])
    }

    private func response(_ object: Any, status: Int = 200) throws -> GitHubResponse {
        GitHubResponse(status: status, body: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}
