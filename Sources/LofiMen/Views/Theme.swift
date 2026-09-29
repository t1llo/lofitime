import LofiMenCore
import SwiftUI

extension Font {
    static func room(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .light: face = "HelveticaNeue-Light"
        case .medium: face = "HelveticaNeue-Medium"
        case .semibold, .bold: face = "HelveticaNeue-Bold"
        default: face = "HelveticaNeue"
        }
        return .custom(face, size: size)
    }
}

struct RoomTheme {
    let background: Color
    let sidebar: Color
    let surface: Color
    let elevated: Color
    let accent: Color
    let text: Color
    let secondary: Color
    let muted: Color
    let line: Color
    let amber: Color
    let activity: Color

    static let tokyoNight = RoomTheme(
        background: Color(hex: 0x1A1B26), sidebar: Color(hex: 0x16161E), surface: Color(hex: 0x1F2335),
        elevated: Color(hex: 0x292E42), accent: Color(hex: 0x7AA2F7),
        text: Color(hex: 0xC0CAF5), secondary: Color(hex: 0xA9B1D6),
        muted: Color(hex: 0x737AA2), line: Color(hex: 0x3B4261).opacity(0.55),
        amber: Color(hex: 0xE0AF68), activity: Color(hex: 0x9ECE6A)
    )

    static let catppuccin = RoomTheme(
        background: Color(hex: 0x1E1E2E), sidebar: Color(hex: 0x11111B), surface: Color(hex: 0x181825),
        elevated: Color(hex: 0x313244), accent: Color(hex: 0xCBA6F7),
        text: Color(hex: 0xCDD6F4), secondary: Color(hex: 0xBAC2DE),
        muted: Color(hex: 0x7F849C), line: Color(hex: 0x45475A).opacity(0.65),
        amber: Color(hex: 0xF9E2AF), activity: Color(hex: 0xA6E3A1)
    )

    func activityColor(level: Int) -> Color {
        level == 0 ? elevated : activity.opacity([0, 0.25, 0.45, 0.7, 1][min(4, max(0, level))])
    }
}

extension AppAppearance {
    var palette: RoomTheme { self == .tokyoNight ? .tokyoNight : .catppuccin }
}

private struct RoomThemeKey: EnvironmentKey {
    static let defaultValue = RoomTheme.tokyoNight
}

extension EnvironmentValues {
    var roomTheme: RoomTheme {
        get { self[RoomThemeKey.self] }
        set { self[RoomThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

struct RoomCard: ViewModifier {
    @Environment(\.roomTheme) private var theme
    var padding: CGFloat = 0
    func body(content: Content) -> some View {
        content.padding(padding).background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line, lineWidth: 1))
    }
}

extension View {
    func roomCard(padding: CGFloat = 0) -> some View { modifier(RoomCard(padding: padding)) }
}

struct CalmButtonStyle: ButtonStyle {
    @Environment(\.roomTheme) private var theme
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.room(size: 13, weight: .medium))
            .foregroundStyle(prominent ? theme.background : theme.text)
            .padding(.horizontal, 16).frame(height: 38).frame(maxWidth: .infinity)
            .background(prominent ? theme.accent : theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct IconButton: View {
    @Environment(\.roomTheme) private var theme
    let symbol: String
    let label: String
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(theme.secondary)
            .help(label).accessibilityLabel(label)
    }
}

struct BrandMark: View {
    @Environment(\.roomTheme) private var theme
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(theme.accent)
            HStack(spacing: size * 0.065) {
                ForEach(Array([0.26, 0.46, 0.63, 0.4, 0.23].enumerated()), id: \.offset) { _, height in
                    Capsule().fill(theme.background).frame(width: size * 0.075, height: size * height)
                }
            }
        }.frame(width: size, height: size)
    }
}

struct StationArtwork: View {
    @Environment(\.roomTheme) private var theme
    let station: RadioStation
    var body: some View {
        GeometryReader { geometry in
            if let image = AppResources.artwork(station) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else {
                theme.elevated.overlay {
                    Image(systemName: station.symbol).font(.system(size: 28)).foregroundStyle(theme.accent)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct VolumeControl: View {
    @Environment(\.roomTheme) private var theme
    @Bindable var player: RadioPlayer
    var body: some View {
        HStack(spacing: 7) {
            IconButton(symbol: player.volume == 0 ? "speaker.slash" : "speaker.wave.1",
                       label: player.volume == 0 ? "Unmute" : "Mute", size: 24) { player.toggleMute() }
            Slider(value: $player.volume, in: 0...1).tint(theme.accent).controlSize(.mini)
                .accessibilityLabel("Music volume")
            Image(systemName: "speaker.wave.3").font(.system(size: 10))
                .foregroundStyle(theme.muted).accessibilityHidden(true)
        }
    }
}

struct MusicControls: View {
    @Environment(\.roomTheme) private var theme
    var player: RadioPlayer
    var showArtwork = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 11) {
                if showArtwork {
                    StationArtwork(station: player.station).frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Menu {
                        ForEach(RadioStation.allCases) { station in
                            Button { player.select(station) } label: {
                                Label(station.title, systemImage: station == player.station ? "checkmark" : station.symbol)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(player.station.title).font(.room(size: 13, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.muted)
                        }
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Choose a radio station").accessibilityLabel("Station: \(player.station.title)")
                    Text(player.isLoading ? "Connecting…" : "Lofi Girl · \(player.isPlaying ? "live" : "radio")")
                        .font(.room(size: 11)).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 4)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying || player.isLoading ? "pause.fill" : "play.fill")
                        .font(.system(size: 13)).frame(width: 34, height: 34)
                        .foregroundStyle(theme.accent).background(theme.elevated, in: Circle())
                }.buttonStyle(.plain).help(player.isPlaying ? "Pause music" : "Play music")
                    .accessibilityLabel(player.isPlaying ? "Pause music" : "Play music")
            }
            VolumeControl(player: player)
            if let error = player.error {
                HStack(alignment: .top) {
                    Text(error).font(.room(size: 11)).foregroundStyle(theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Retry") { player.retry() }.buttonStyle(.plain).foregroundStyle(theme.accent)
                }
            }
        }
    }
}
