import Foundation
import LofiMenCore
import Observation

@MainActor @Observable
public final class GitHubSyncService {
    public var repositoryName: String {
        didSet { defaults.set(repositoryName, forKey: "sync.github.name") }
    }
    public private(set) var connection: GitHubSyncConnection?
    public private(set) var isBusy = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var error: String?
    public var isEnabled: Bool { connection != nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: GitHubSyncClient
    @ObservationIgnored private var snapshot: () -> [SessionRecord] = { [] }
    @ObservationIgnored private var receive: ([SessionRecord]) -> Void = { _ in }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var periodicTimer: Timer?
    @ObservationIgnored private var needsAnotherSync = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var started = false

    public init(defaults: UserDefaults = .standard, client: GitHubSyncClient = GitHubSyncClient()) {
        self.defaults = defaults
        self.client = client
        repositoryName = defaults.string(forKey: "sync.github.name") ?? "lofitime-sync"
        connection = defaults.data(forKey: "sync.github.connection.v1")
            .flatMap { try? JSONDecoder().decode(GitHubSyncConnection.self, from: $0) }
        lastSyncedAt = defaults.object(forKey: "sync.github.lastSynced") as? Date
    }

    public func start(snapshot: @escaping () -> [SessionRecord], receive: @escaping ([SessionRecord]) -> Void) {
        guard !started else { return }
        started = true
        self.snapshot = snapshot
        self.receive = receive
        schedulePeriodicSync()
        syncNow()
    }

    public func create() {
        repositoryName = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        beginConnection(create: true, repository: repositoryName)
    }

    public func connect(repository: String) {
        beginConnection(create: false, repository: repository)
    }

    private func beginConnection(create: Bool, repository: String) {
        guard started, !isBusy, !isEnabled else { return }
        let generation = generation
        isBusy = true
        error = nil
        task = Task { [weak self, client] in
            do {
                let connection: GitHubSyncConnection
                if create { connection = try await client.create(name: repository) }
                else { connection = try await client.connect(repository: repository) }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.connection = connection
                self.defaults.set(try JSONEncoder().encode(connection), forKey: "sync.github.connection.v1")
                self.lastSyncedAt = nil
                self.defaults.removeObject(forKey: "sync.github.lastSynced")
                self.isBusy = false
                self.task = nil
                self.schedulePeriodicSync()
                self.syncNow()
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.isBusy = false
                self.task = nil
            }
        }
    }

    public func disconnect() {
        generation += 1
        task?.cancel()
        task = nil
        periodicTimer?.invalidate()
        periodicTimer = nil
        connection = nil
        isBusy = false
        needsAnotherSync = false
        lastSyncedAt = nil
        lastAttempt = nil
        error = nil
        defaults.removeObject(forKey: "sync.github.connection.v1")
        defaults.removeObject(forKey: "sync.github.lastSynced")
    }

    /// Activation/wake can arrive together; coalesce them without postponing a completed session.
    public func refreshIfNeeded() {
        guard !isBusy, lastAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        syncNow()
    }

    public func syncNow() {
        guard started, let connection else { return }
        if isBusy { needsAnotherSync = true; return }
        isBusy = true
        error = nil
        let generation = generation
        task = Task { [weak self, client] in
            repeat {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.needsAnotherSync = false
                self.lastAttempt = Date()
                let records = self.snapshot()
                do {
                    let merged = try await client.synchronize(connection, records: records)
                    guard self.generation == generation, !Task.isCancelled else { return }
                    // A focus session can finish while the request is in flight. Preserve it too.
                    let current = try SessionSyncArchive.merge(self.snapshot(), merged)
                    self.receive(current)
                    self.needsAnotherSync = self.needsAnotherSync || current != merged
                    self.lastSyncedAt = Date()
                    self.defaults.set(self.lastSyncedAt, forKey: "sync.github.lastSynced")
                    self.error = nil
                } catch {
                    guard self.generation == generation, !Task.isCancelled else { return }
                    self.error = error.localizedDescription
                    // Local persistence is the retry queue; launch/wake/the next interval retries it.
                    break
                }
            } while self?.needsAnotherSync == true
            guard let self, self.generation == generation else { return }
            self.isBusy = false
            self.task = nil
        }
    }

    private func schedulePeriodicSync() {
        periodicTimer?.invalidate()
        guard isEnabled else { periodicTimer = nil; return }
        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfNeeded() }
        }
        timer.tolerance = 30
        periodicTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit {
        task?.cancel()
        periodicTimer?.invalidate()
    }
}
