import Foundation

public enum AppAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case candlelight, catppuccin, moss, moonlight, rosewood, tokyoNight
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .candlelight: "Candlelight"
        case .catppuccin: "Catppuccin"
        case .moss: "Moss"
        case .moonlight: "Moonlight"
        case .rosewood: "Rosewood"
        case .tokyoNight: "Tokyo Night"
        }
    }
    public var subtitle: String {
        switch self {
        case .candlelight: "Honey & warm earth"
        case .catppuccin: "Soft lavender & mocha"
        case .moss: "Sage & forest green"
        case .moonlight: "Mist & midnight blue"
        case .rosewood: "Dusty rose & plum"
        case .tokyoNight: "Deep navy & neon blue"
        }
    }
}

public struct Preferences: Codable, Sendable {
    public var timer = FocusConfiguration()
    public var appearance: AppAppearance = .candlelight
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
        // Unknown themes fall back without losing other preferences.
        appearance = (try? values.decode(AppAppearance.self, forKey: .appearance)) ?? .candlelight
        autoStartBreaks = try values.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? false
        autoStartFocus = try values.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? false
        startMusicWithFocus = try values.decodeIfPresent(Bool.self, forKey: .startMusicWithFocus) ?? true
        completionSound = try values.decodeIfPresent(Bool.self, forKey: .completionSound) ?? true
        notifications = try values.decodeIfPresent(Bool.self, forKey: .notifications) ?? false
        showMenuBarCountdown = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarCountdown) ?? true
        dailyGoal = try values.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 4
    }
}
