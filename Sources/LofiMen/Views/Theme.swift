import LofiMenCore
import SwiftUI

extension Font {
    static func room(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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

    static let candlelight = RoomTheme(
        background: Color(hex: 0x211F1C), sidebar: Color(hex: 0x191815), surface: Color(hex: 0x2B2923),
        elevated: Color(hex: 0x38352D), accent: Color(hex: 0xDFBC87),
        text: Color(hex: 0xF3EDE1), secondary: Color(hex: 0xCFC5B3),
        muted: Color(hex: 0xAA9F8D), line: Color(hex: 0x625A48).opacity(0.55),
        amber: Color(hex: 0xE7B478), activity: Color(hex: 0xAABD92)
    )

    static let catppuccin = RoomTheme(
        background: Color(hex: 0x1E1E2E), sidebar: Color(hex: 0x181825), surface: Color(hex: 0x272738),
        elevated: Color(hex: 0x36364B), accent: Color(hex: 0xCBA6F7),
        text: Color(hex: 0xE1E5F5), secondary: Color(hex: 0xBAC2DE),
        muted: Color(hex: 0xA0A5BE), line: Color(hex: 0x585B70).opacity(0.65),
        amber: Color(hex: 0xF9E2AF), activity: Color(hex: 0xA6D3AB)
    )

    static let moss = RoomTheme(
        background: Color(hex: 0x19221E), sidebar: Color(hex: 0x141C18), surface: Color(hex: 0x232E27),
        elevated: Color(hex: 0x303E34), accent: Color(hex: 0xB8CE9B),
        text: Color(hex: 0xE8EEDF), secondary: Color(hex: 0xC1CCB9),
        muted: Color(hex: 0x9DAD99), line: Color(hex: 0x52654F).opacity(0.6),
        amber: Color(hex: 0xDAC58B), activity: Color(hex: 0xA3C58C)
    )

    static let moonlight = RoomTheme(
        background: Color(hex: 0x19222D), sidebar: Color(hex: 0x141B25), surface: Color(hex: 0x232F3C),
        elevated: Color(hex: 0x303F50), accent: Color(hex: 0xA5C9D7),
        text: Color(hex: 0xE6EDF2), secondary: Color(hex: 0xBDCCD8),
        muted: Color(hex: 0x9AACBD), line: Color(hex: 0x52677C).opacity(0.6),
        amber: Color(hex: 0xE3C896), activity: Color(hex: 0x94C1B3)
    )

    static let rosewood = RoomTheme(
        background: Color(hex: 0x292126), sidebar: Color(hex: 0x20191E), surface: Color(hex: 0x352B31),
        elevated: Color(hex: 0x44373F), accent: Color(hex: 0xDFB0B5),
        text: Color(hex: 0xF3E6E8), secondary: Color(hex: 0xD5BFC8),
        muted: Color(hex: 0xB69EA9), line: Color(hex: 0x745763).opacity(0.55),
        amber: Color(hex: 0xE5BF97), activity: Color(hex: 0xB3C39F)
    )

    func activityColor(level: Int) -> Color {
        level == 0 ? elevated : activity.opacity([0, 0.25, 0.45, 0.7, 1][min(4, max(0, level))])
    }
}

extension AppAppearance {
    var palette: RoomTheme {
        switch self {
        case .candlelight: .candlelight
        case .catppuccin: .catppuccin
        case .moss: .moss
        case .moonlight: .moonlight
        case .rosewood: .rosewood
        }
    }
}

private struct RoomThemeKey: EnvironmentKey {
    static let defaultValue = RoomTheme.candlelight
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
    var size: CGFloat = 26
    var body: some View {
        Image(nsImage: AppResources.appIcon)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
