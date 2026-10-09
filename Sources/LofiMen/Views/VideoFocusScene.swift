import LofiMenCore
import SwiftUI

/// One edge-to-edge live scene, used by both the compact studio and menu-bar panel.
struct VideoFocusScene: View {
    @Environment(\.roomTheme) private var theme
    @Bindable var model: AppModel
    let presentation: VideoPresentation
    var openStudio: (() -> Void)?
    private var compact: Bool { presentation == .menuBar }

    var body: some View {
        ZStack {
            VideoBackdrop(player: model.player, presentation: presentation, fillsBounds: true)
                // Clipping oversized artwork does not clip its hit-testing area.
                .allowsHitTesting(false)

            Color.black.opacity(compact ? 0.62 : 0.34).allowsHitTesting(false)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.18), location: 0),
                .init(color: .clear, location: 0.25),
                .init(color: .black.opacity(0.15), location: 0.43),
                .init(color: .black.opacity(0.65), location: 0.82),
                .init(color: .black.opacity(0.8), location: 1)
            ], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer(minLength: compact ? 8 : 24)
                VStack(spacing: compact ? 12 : 17) {
                    if let banner = model.banner {
                        HStack(spacing: 6) {
                            Text(banner).font(.room(size: 10))
                            Spacer(minLength: 0)
                            Button { model.banner = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                .buttonStyle(.plain)
                        }.foregroundStyle(.white.opacity(0.8))
                    }
                    FocusControls(model: model, compact: compact)
                    radioControls
                }.frame(maxWidth: 340)
            }.padding(compact ? 16 : 20)
        }
        .font(.room(size: 12)).foregroundStyle(theme.text).tint(theme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Menu {
                ForEach(RadioStation.allCases) { station in
                    Button { model.player.select(station) } label: {
                        Label(station.title, systemImage: station == model.player.station ? "checkmark" : station.symbol)
                    }
                }
            } label: {
                Text(model.player.station.title).font(.room(size: compact ? 15 : 18, weight: .semibold))
                    .padding(.vertical, 6)
            }.menuStyle(.borderlessButton).fixedSize().tint(theme.text)
                .help("Choose a genre").accessibilityLabel("Genre: \(model.player.station.title)")
            Spacer(minLength: 0)
            if compact {
                if let openStudio {
                    OverlayIconButton(symbol: "slider.horizontal.3", label: "Open Studio settings", size: 30, action: openStudio)
                        .accessibilityIdentifier("menu-bar-settings")
                }
                Menu {
                    Button("Quit Lofitime") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.12)))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Quit Lofitime")
            }
        }
    }

    private var radioControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 14) {
                Button { model.player.toggle() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: model.player.isPlaying || model.player.isLoading ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.background)
                            .frame(width: compact ? 34 : 38, height: compact ? 34 : 38)
                            .background(theme.text, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.player.isLoading ? "Connecting…" : model.player.isPlaying ? "Pause music" : "Play music")
                                .font(.room(size: compact ? 12 : 11, weight: .medium))
                            if !compact {
                                Text(model.player.isPlaying ? "Lofi Girl · live" : "Lofi Girl radio")
                                    .font(.room(size: 9)).foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }.foregroundStyle(theme.text)
                }.buttonStyle(.plain)
                    .help(model.player.isPlaying || model.player.isLoading ? "Pause radio" : "Play radio")
                    .accessibilityLabel(model.player.isPlaying || model.player.isLoading ? "Pause radio" : "Play radio")
                    .accessibilityIdentifier("radio-play-pause")
                Spacer(minLength: 2)
                HStack(spacing: 4) {
                    Button { model.player.toggleMute() } label: {
                        Image(systemName: model.player.volume == 0 ? "speaker.slash" : "speaker.wave.1")
                            .font(.system(size: 11)).frame(width: 23, height: 26)
                    }.buttonStyle(.plain).help(model.player.volume == 0 ? "Unmute" : "Mute")
                    Slider(value: Binding(get: { model.player.volume }, set: { model.player.volume = $0 }), in: 0...1).controlSize(.mini)
                        .accessibilityLabel("Radio volume")
                }.frame(width: compact ? 112 : 138).foregroundStyle(.white.opacity(0.75))
            }
            if model.player.pausedForOutputChange {
                Label("Headphones disconnected. Press Play to resume.", systemImage: "headphones")
                    .font(.room(size: 10)).foregroundStyle(theme.text.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = model.player.error {
                HStack(alignment: .top) {
                    Text(error).font(.room(size: 10)).foregroundStyle(theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { model.player.retry() }.buttonStyle(.plain).font(.room(size: 10))
                }
            }
        }.padding(.top, compact ? 10 : 12)
    }
}

struct OverlayIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85)).frame(width: size, height: size)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.12)))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
