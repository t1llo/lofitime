import LofiMenCore
import SwiftUI

/// One edge-to-edge live scene, used by both the compact studio and menu-bar panel.
struct VideoFocusScene: View {
    @Environment(\.roomTheme) private var theme
    @Bindable var model: AppModel
    let presentation: VideoPresentation
    var openStudio: (() -> Void)?
    @State var showingSettings = false
    @State private var showingVideo = false
    private var compact: Bool { presentation == .menuBar }

    var body: some View {
        ZStack {
            VideoBackdrop(player: model.player, presentation: presentation, fillsBounds: !showingVideo)
                // Clipping oversized artwork does not clip its hit-testing area.
                .allowsHitTesting(showingVideo)

            if !showingVideo {
                Color.black.opacity(compact ? 0.44 : 0.34).allowsHitTesting(false)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.18), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.15), location: 0.43),
                    .init(color: .black.opacity(0.65), location: 0.82),
                    .init(color: .black.opacity(0.8), location: 1)
                ], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                header
                if showingVideo {
                    Spacer()
                    radioControls
                } else if showingSettings {
                    ScrollView {
                        PanelSettings(model: model, compact: compact) { showingSettings = false }
                            .frame(maxWidth: 340).padding(.top, compact ? 10 : 18)
                    }.scrollIndicators(.hidden)
                } else {
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
                        footer
                    }.frame(maxWidth: 340)
                }
            }.padding(compact ? 16 : 20)
        }
        .font(.room(size: 12)).foregroundStyle(.white).tint(theme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if showingVideo {
                Button { showingVideo = false } label: {
                    Label("Back to timer", systemImage: "chevron.left").font(.room(size: 11, weight: .medium))
                        .padding(10).background(.black.opacity(0.5), in: Capsule())
                }.buttonStyle(.plain)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Circle().fill(model.player.isPlaying ? theme.activity : .white.opacity(0.5)).frame(width: 4, height: 4)
                        Text("GENRE · LOFI GIRL").font(.room(size: 8, weight: .medium)).tracking(1)
                    }.foregroundStyle(.white.opacity(0.75))
                    Menu {
                        ForEach(RadioStation.allCases) { station in
                            Button { model.player.select(station) } label: {
                                Label(station.title, systemImage: station == model.player.station ? "checkmark" : station.symbol)
                            }
                        }
                    } label: {
                        Text(model.player.station.title).font(.room(size: 14, weight: .medium))
                    }.menuStyle(.borderlessButton).fixedSize().tint(.white)
                        .help("Choose a genre").accessibilityLabel("Genre: \(model.player.station.title)")
                }.shadow(color: .black.opacity(0.4), radius: 5)
                Spacer(minLength: 0)
                OverlayIconButton(symbol: "rectangle.inset.filled", label: "Show full video", size: compact ? 26 : 30) {
                    showingSettings = false
                    showingVideo = true
                    if !model.player.hasLoaded { model.player.play() }
                }
                OverlayIconButton(symbol: showingSettings ? "xmark" : "slider.horizontal.3", label: showingSettings ? "Close settings" : "Timer settings", size: compact ? 26 : 30) {
                    showingSettings.toggle()
                }
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
                            .foregroundStyle(.black.opacity(0.85))
                            .frame(width: compact ? 34 : 38, height: compact ? 34 : 38)
                            .background(.white.opacity(0.92), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.player.isLoading ? "Connecting…" : model.player.isPlaying ? "Pause music" : "Play music")
                                .font(.room(size: 11, weight: .medium))
                            Text(model.player.isPlaying ? "Lofi Girl · live" : "Lofi Girl radio")
                                .font(.room(size: 9)).foregroundStyle(.white.opacity(0.65))
                        }
                    }.foregroundStyle(.white)
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
            if let error = model.player.error {
                HStack(alignment: .top) {
                    Text(error).font(.room(size: 10)).foregroundStyle(theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") { model.player.retry() }.buttonStyle(.plain).font(.room(size: 10))
                }
            }
        }.padding(.top, compact ? 10 : 12)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }

    private var footer: some View {
        HStack {
            if let openStudio {
                Button(action: openStudio) {
                    Label("Open studio", systemImage: "arrow.up.left.and.arrow.down.right")
                }.buttonStyle(.plain)
            } else {
                TextField("", text: $model.intention).textFieldStyle(.plain)
                    .font(.room(size: 10)).frame(height: 16)
                    .overlay(alignment: .leading) {
                        if model.intention.isEmpty {
                            Text("Session name (optional)").font(.room(size: 10)).allowsHitTesting(false)
                        }
                    }.accessibilityLabel("Session name").lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Skip session") { model.skipSession() }
                Button("Quit Lofi Men") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 16) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options")
        }.font(.room(size: 9)).foregroundStyle(.white.opacity(0.65))
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

struct PanelSettings: View {
    @Environment(\.roomTheme) private var theme
    @Bindable var model: AppModel
    var compact = false
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 13) {
            HStack {
                Text("Your timer").font(.room(size: compact ? 13 : 15, weight: .semibold))
                Spacer()
                Button("Done", action: done).buttonStyle(.plain).font(.room(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
            if !compact {
                Text("Saved durations for each session").font(.room(size: 10)).foregroundStyle(.white.opacity(0.65))
            }
            durationRow("Focus", value: $model.preferences.timer.focusMinutes)
            durationRow("Short break", value: $model.preferences.timer.shortBreakMinutes)
            durationRow("Long break", value: $model.preferences.timer.longBreakMinutes)
            HStack {
                Text("Long break every").font(.room(size: 11))
                Spacer()
                IntegerField(label: "Sessions before a long break", value: $model.preferences.timer.sessionsBeforeLongBreak,
                             range: 2...8, unit: "sessions", compact: compact)
            }
            Divider().overlay(.white.opacity(0.1))
            Toggle("Start music with focus", isOn: $model.preferences.startMusicWithFocus)
            Toggle("Automatically start breaks", isOn: $model.preferences.autoStartBreaks)
            Picker("Theme", selection: $model.preferences.appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
        }
        .font(.room(size: 11)).toggleStyle(.switch).controlSize(.mini)
        .padding(compact ? 12 : 18).background(theme.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.15)))
        .foregroundStyle(.white.opacity(0.9))
    }

    private func durationRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.room(size: 11))
            Spacer()
            IntegerField(label: "\(title) duration in minutes", value: value, range: 1...180, unit: "min", compact: compact)
        }
    }
}
