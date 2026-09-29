import Foundation

public enum AppAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case tokyoNight, catppuccin
    public var id: String { rawValue }
    public var title: String { self == .tokyoNight ? "Tokyo Night" : "Catppuccin" }
}

public struct Preferences: Codable, Sendable {
    public var timer = FocusConfiguration()
    public var appearance: AppAppearance = .tokyoNight
    public var autoStartBreaks = false
    public var autoStartFocus = false
    public var startMusicWithFocus = true
    public var completionSound = true
    public var notifications = false
    public var showMenuBarCountdown = true
    public var dailyGoal = 4

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case timer, appearance, autoStartBreaks, autoStartFocus, startMusicWithFocus
        case completionSound, notifications, showMenuBarCountdown, dailyGoal
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        timer = try values.decodeIfPresent(FocusConfiguration.self, forKey: .timer) ?? .init()
        // Adding a theme must not erase existing timer and notification preferences.
        appearance = (try? values.decode(AppAppearance.self, forKey: .appearance)) ?? .tokyoNight
        autoStartBreaks = try values.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? false
        autoStartFocus = try values.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? false
        startMusicWithFocus = try values.decodeIfPresent(Bool.self, forKey: .startMusicWithFocus) ?? true
        completionSound = try values.decodeIfPresent(Bool.self, forKey: .completionSound) ?? true
        notifications = try values.decodeIfPresent(Bool.self, forKey: .notifications) ?? false
        showMenuBarCountdown = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarCountdown) ?? true
        dailyGoal = try values.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 4
    }
}
