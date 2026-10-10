import AppKit
import LofiMenCore
import LofiMenSync
import Observation
import UserNotifications

enum StudioSection: String, CaseIterable, Identifiable {
    case sessions = "Room", statistics = "Stats", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sessions: "house"
        case .statistics: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

private struct SessionArchive: Codable {
    var timer: FocusTimer
    var records: [SessionRecord]
    var intention: String
}

@MainActor @Observable
final class AppModel {
    var section: StudioSection = .sessions
    var menuBarShowsRoom = false {
        didSet { defaults.set(menuBarShowsRoom, forKey: "menuBar.showsRoom") }
    }
    var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                defaults.set(data, forKey: "preferences.v1")
            }
            if oldValue.timer != preferences.timer {
                durationInput = nil
                timer.reconfigure(preferences.timer)
            }
            if oldValue.appearance != preferences.appearance { updateAppIcon() }
            saveSession()
        }
    }
    private(set) var timer: FocusTimer
    // Shared by both countdown fields and keyboard commands; never persisted until applied.
    var durationInput: String?
    private(set) var records: [SessionRecord]
    private(set) var activity: FocusActivity
    private(set) var todayRecords: [SessionRecord]
    private(set) var todayDuration: TimeInterval
    var intention: String { didSet { saveSession() } }
    private(set) var now = Date()
    var banner: String?
    var notificationError: String?
    private(set) var notificationPermissionDenied = false
    let player: RadioPlayer
    let sync: GitHubSyncService

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var notificationRequest: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarShowsRoom = defaults.bool(forKey: "menuBar.showsRoom")
        player = RadioPlayer(defaults: defaults)
        sync = GitHubSyncService(defaults: defaults)
        let preferences = defaults.data(forKey: "preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        self.preferences = preferences
        let archive = defaults.data(forKey: "session.v1")
            .flatMap { try? JSONDecoder().decode(SessionArchive.self, from: $0) }
        timer = archive?.timer ?? FocusTimer(configuration: preferences.timer)
        let records = (archive?.records ?? [])
            .filter { $0.duration.isFinite && $0.duration > 0 }
            .sorted { $0.finishedAt > $1.finishedAt }
        self.records = records
        activity = FocusActivity(records: records, through: Date())
        intention = archive?.intention ?? ""
        let today = records.filter { Calendar.current.isDateInToday($0.finishedAt) && $0.finishedAt <= Date() }
        todayRecords = today
        todayDuration = today.reduce(0) { $0 + $1.duration }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
                self?.sync.refreshIfNeeded()
            }
        }
        tick()
        updateAppIcon()
        if !DebugTools.requested {
            sync.start(snapshot: { [weak self] in self?.records ?? [] }, receive: { [weak self] records in
                self?.receiveSyncedRecords(records)
            })
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.sync.refreshIfNeeded() }
            }
        }
        if !DebugTools.requested, Bundle.main.bundleURL.pathExtension == "app",
           !defaults.bool(forKey: "notifications.configured") {
            setNotifications(true)
        }
    }

    var remainingText: String {
        SessionDuration.clock(timer.remaining(at: now))
    }

    private func updateAppIcon() {
        guard !DebugTools.requested else { return }
        NSApplication.shared.applicationIconImage = AppResources.themedIcon(for: preferences.appearance.palette)
    }

    var progress: Double { timer.progress(at: now) }
    var cycleNumber: Int { min(timer.completedInCycle + 1, preferences.timer.cycleLength) }
    var timerActionTitle: String {
        switch timer.status {
        case .running: "Pause"
        case .paused: "Resume"
        case .ready: timer.mode == .focus ? "Start focus" : "Start break"
        }
    }

    func toggleTimer() {
        let activeDeadline = timer.status == .running ? timer.deadline : nil
        tick()
        // A click on Pause at the deadline must not start (or pause) the next mode.
        if let activeDeadline, timer.deadline != activeDeadline { return }
        if timer.status == .running {
            timer.pause(at: now)
        } else {
            guard applyDurationInput() else { return }
            timer.start(at: now)
            if timer.mode == .focus && preferences.startMusicWithFocus { player.playWithFocus() }
        }
        banner = nil
        saveSession()
    }

    func resetTimer() {
        tick()
        durationInput = nil
        timer.restart()
        now = Date()
        saveSession()
    }

    func selectMode(_ mode: FocusMode) {
        tick()
        guard timer.mode != mode else { return }
        durationInput = nil
        timer.select(mode, configuration: preferences.timer)
        now = Date()
        banner = nil
        saveSession()
    }

    func setDuration(_ seconds: TimeInterval) {
        tick()
        guard timer.setDuration(seconds) else { return }
        durationInput = nil
        now = Date()
        banner = nil
        saveSession()
    }

    func skipSession() {
        tick()
        durationInput = nil
        timer.skip(configuration: preferences.timer)
        now = Date()
        saveSession()
    }

    @discardableResult func applyDurationInput() -> Bool {
        guard let durationInput else { return true }
        guard let seconds = SessionDuration.parse(durationInput) else { return false }
        setDuration(seconds)
        return true
    }

    func tick() {
        defer { scheduleTick() }
        let previousDay = activity.endDate
        now = Date()
        if Calendar.current.startOfDay(for: now) != previousDay {
            activity = FocusActivity(records: records, through: now)
            refreshToday()
        }
        // Calling a mutating method on an observable property invalidates its
        // readers even when the method does nothing. Only mutate at the deadline.
        guard timer.status == .running, let deadline = timer.deadline, now >= deadline else { return }
        guard let completion = timer.tick(
            at: now, configuration: preferences.timer,
            autoStartBreaks: preferences.autoStartBreaks,
            autoStartFocus: preferences.autoStartFocus
        ) else { return }

        if completion.mode == .focus {
            records.insert(SessionRecord(
                finishedAt: completion.finishedAt,
                duration: completion.duration,
                intention: intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Focus session" : intention.trimmingCharacters(in: .whitespacesAndNewlines)
            ), at: 0)
            activity = FocusActivity(records: records, through: now)
            refreshToday()
        }
        let message = completion.mode == .focus
            ? "Session complete. Time for a break."
            : "Break complete. Ready to focus?"
        banner = message
        if preferences.completionSound { NSSound(named: "Glass")?.play() }
        if preferences.notifications { notify(message) }
        if timer.status == .running && timer.mode == .focus && preferences.startMusicWithFocus {
            player.playWithFocus()
        }
        saveSession()
        if completion.mode == .focus { sync.syncNow() }
    }

    func setNotifications(_ enabled: Bool) {
        notificationRequest?.cancel()
        defaults.set(true, forKey: "notifications.configured")
        notificationError = nil
        guard enabled else { preferences.notifications = false; return }
        guard Bundle.main.bundleIdentifier != nil else {
            notificationError = "Open the bundled Lofitime app to enable notifications."
            return
        }
        notificationRequest = Task {
            do {
                let allowed = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert])
                guard !Task.isCancelled else { return }
                preferences.notifications = allowed
                notificationPermissionDenied = !allowed
                if !allowed { notificationError = "Allow Lofitime in System Settings → Notifications." }
            } catch {
                guard !Task.isCancelled else { return }
                notificationError = error.localizedDescription
            }
        }
    }

    func refreshNotificationAuthorization() async {
        guard !DebugTools.requested, Bundle.main.bundleIdentifier != nil else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermissionDenied = settings.authorizationStatus == .denied
        if notificationPermissionDenied {
            preferences.notifications = false
            notificationError = "Allow Lofitime in System Settings → Notifications."
        } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            notificationError = nil
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func notify(_ message: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Lofitime · \(timer.mode == .focus ? "Back to focus" : "Time to unwind")"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func refreshToday() {
        todayRecords = records.filter { Calendar.current.isDate($0.finishedAt, inSameDayAs: now) && $0.finishedAt <= now }
        todayDuration = todayRecords.reduce(0) { $0 + $1.duration }
    }

    private func receiveSyncedRecords(_ incoming: [SessionRecord]) {
        guard records != incoming else { return }
        records = incoming
        now = Date()
        activity = FocusActivity(records: records, through: now)
        refreshToday()
        saveSession()
    }

    private func scheduleTick() {
        ticker?.invalidate()
        let date = Date()
        let nextDay = Calendar.current.date(byAdding: .day, value: 1,
                                           to: Calendar.current.startOfDay(for: date))!
        let fireDate: Date
        if timer.status == .running, let deadline = timer.deadline {
            fireDate = min(date.addingTimeInterval(1), deadline, nextDay)
        } else {
            // Ready and paused timers need no countdown work; refresh at midnight.
            fireDate = nextDay
        }
        let ticker = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ticker.tolerance = 0.1
        self.ticker = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }

    deinit {
        ticker?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        notificationRequest?.cancel()
    }

    private func saveSession() {
        scheduleTick()
        let archive = SessionArchive(timer: timer, records: records, intention: intention)
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: "session.v1") }
    }
}
