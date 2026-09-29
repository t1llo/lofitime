import Foundation

public enum FocusMode: String, CaseIterable, Codable, Sendable {
    case focus, shortBreak, longBreak

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

public struct FocusConfiguration: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var sessionsBeforeLongBreak: Int

    public init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5,
                longBreakMinutes: Int = 15, sessionsBeforeLongBreak: Int = 4) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.sessionsBeforeLongBreak = sessionsBeforeLongBreak
    }

    public func duration(for mode: FocusMode) -> TimeInterval {
        let minutes: Int
        switch mode {
        case .focus: minutes = focusMinutes
        case .shortBreak: minutes = shortBreakMinutes
        case .longBreak: minutes = longBreakMinutes
        }
        return TimeInterval(max(1, min(minutes, 180)) * 60)
    }

    public var cycleLength: Int { max(2, min(sessionsBeforeLongBreak, 8)) }
}

public enum TimerStatus: String, Codable, Sendable {
    case ready, running, paused
}

public struct SessionCompletion: Equatable, Sendable {
    public let mode: FocusMode
    public let duration: TimeInterval
    public let finishedAt: Date
}

/// A deadline-based clock: sleeping or hiding the app never causes timer drift.
public struct FocusTimer: Codable, Sendable {
    public private(set) var mode: FocusMode = .focus
    public private(set) var status: TimerStatus = .ready
    public private(set) var completedInCycle = 0
    public private(set) var duration: TimeInterval
    public private(set) var deadline: Date?
    private var remainingWhenPaused: TimeInterval

    public init(configuration: FocusConfiguration = .init()) {
        duration = configuration.duration(for: .focus)
        remainingWhenPaused = duration
    }

    public func remaining(at date: Date) -> TimeInterval {
        if let deadline, status == .running {
            return max(0, min(duration, deadline.timeIntervalSince(date)))
        }
        return remainingWhenPaused
    }

    public func progress(at date: Date) -> Double {
        min(1, max(0, 1 - remaining(at: date) / duration))
    }

    public mutating func start(at date: Date) {
        guard status != .running else { return }
        deadline = date.addingTimeInterval(remainingWhenPaused)
        status = .running
    }

    public mutating func pause(at date: Date) {
        guard status == .running else { return }
        remainingWhenPaused = remaining(at: date)
        deadline = nil
        status = .paused
    }

    public mutating func select(_ mode: FocusMode, configuration: FocusConfiguration) {
        self.mode = mode
        reset(configuration: configuration)
    }

    public mutating func reset(configuration: FocusConfiguration) {
        duration = configuration.duration(for: mode)
        restart()
    }

    public mutating func restart() {
        remainingWhenPaused = duration
        deadline = nil
        status = .ready
    }

    /// A one-session override; the next mode uses the configured defaults.
    @discardableResult
    public mutating func setDuration(_ seconds: TimeInterval) -> Bool {
        guard seconds.isFinite, (1...10_800).contains(seconds), seconds.rounded() == seconds else { return false }
        duration = seconds
        restart()
        return true
    }

    /// Configuration changes affect a ready timer; an active session keeps its duration.
    public mutating func reconfigure(_ configuration: FocusConfiguration) {
        completedInCycle = min(completedInCycle, configuration.cycleLength - 1)
        if status == .ready { reset(configuration: configuration) }
    }

    /// A skipped session is not recorded as completed work.
    public mutating func skip(configuration: FocusConfiguration) {
        let next: FocusMode = mode == .focus ? .shortBreak : .focus
        select(next, configuration: configuration)
    }

    /// Completes at most one session. Sleep never fabricates unattended focus sessions.
    public mutating func tick(at date: Date, configuration: FocusConfiguration,
                              autoStartBreaks: Bool = false,
                              autoStartFocus: Bool = false) -> SessionCompletion? {
        guard status == .running, let deadline, date >= deadline else { return nil }
        let completion = SessionCompletion(mode: mode, duration: duration, finishedAt: deadline)
        let next: FocusMode
        if mode == .focus {
            completedInCycle += 1
            if completedInCycle >= configuration.cycleLength {
                next = .longBreak
                completedInCycle = 0
            } else {
                next = .shortBreak
            }
        } else {
            next = .focus
        }
        select(next, configuration: configuration)
        if next == .focus ? autoStartFocus : autoStartBreaks { start(at: date) }
        return completion
    }
}
