import AppKit
import LofiMenCore
import SwiftUI

struct MenuBarView: View {
    static let size = CGSize(width: 320, height: 360)
    static let cornerRadius: CGFloat = 20
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var theme: RoomTheme { model.preferences.appearance.palette }

    var body: some View {
        Group {
            if model.menuBarShowsRoom {
                roomPanel
            } else {
                VideoFocusScene(model: model, presentation: .menuBar, openStudio: openSettings,
                                showRoom: { model.menuBarShowsRoom = true })
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .background(MenuBarWindowAppearance())
        .environment(\.roomTheme, model.preferences.appearance.palette)
        .preferredColorScheme(.dark)
    }

    private var roomPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("My little study").font(.room(size: 14, weight: .medium))
                Spacer(minLength: 0)
                OverlayIconButton(symbol: "headphones", label: "Show music and timer", action: { model.menuBarShowsRoom = false })
                    .accessibilityIdentifier("menu-bar-room-toggle")
                OverlayIconButton(symbol: "slider.horizontal.3", label: "Open settings", action: openSettings)
                    .accessibilityIdentifier("menu-bar-settings")
                Menu {
                    Button("Open my room") {
                        model.section = .sessions
                        openWindow(id: "studio")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    Button("Quit Lofitime") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium)).frame(width: 30, height: 30)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.12)))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let growth = FocusRoom(records: model.records, through: max(context.date, model.activity.updatedAt))
                VStack(spacing: 5) {
                    MenuBarRoomScene(growth: growth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack {
                        Text(growth.title)
                        Spacer()
                        Text("\(focusTime(growth.recentDuration)) · 7 days").foregroundStyle(theme.accent)
                    }.font(.room(size: 10)).lineLimit(1)
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.timer.mode.title).font(.room(size: 9)).foregroundStyle(theme.muted)
                    Text(model.remainingText).font(.room(size: 23, weight: .medium)).monospacedDigit()
                }
                Spacer()
                IconButton(symbol: model.timer.status == .running ? "pause.fill" : "play.fill", label: model.timerActionTitle) {
                    model.toggleTimer()
                }.accessibilityIdentifier("room-timer-toggle")
                IconButton(symbol: model.player.isPlaying || model.player.isLoading ? "speaker.wave.2" : "speaker.slash",
                           label: model.player.isPlaying || model.player.isLoading ? "Pause music" : "Play music") {
                    model.player.toggle()
                }.accessibilityIdentifier("room-radio-toggle")
            }.padding(.horizontal, 12).padding(.vertical, 7)
                .background(theme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        }.padding(16).foregroundStyle(theme.text).background(theme.surface)
    }

    private func openSettings() {
        model.section = .settings
        openWindow(id: "studio")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarRoomScene: View {
    @Environment(\.roomTheme) private var theme
    let growth: FocusRoom
    @State private var camera = RoomCameraState()

    var body: some View {
        StudyRoomScene(growth: growth, theme: theme, camera: $camera)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MenuBarWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowAppearanceView { WindowAppearanceView() }
    func updateNSView(_ nsView: WindowAppearanceView, context: Context) { nsView.applyAppearance() }

    final class WindowAppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }

        func applyAppearance() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                window.isOpaque = false
                window.backgroundColor = .clear
                // The window's material and native hosting frame sit outside the
                // SwiftUI clip. Round both so no square outer corners remain.
                for view in [window.contentView, window.contentView?.superview].compactMap({ $0 }) {
                    view.wantsLayer = true
                    view.layer?.cornerRadius = MenuBarView.cornerRadius
                    view.layer?.cornerCurve = .continuous
                    view.layer?.masksToBounds = true
                }
                window.invalidateShadow()
            }
        }
    }
}
