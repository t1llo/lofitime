import AppKit
import LofiMenCore
import SwiftUI

struct MenuBarView: View {
    static let size = CGSize(width: 320, height: 404)
    static let contentSize = CGSize(width: 320, height: 360)
    static let cornerRadius: CGFloat = 20
    @Bindable var model: AppModel
    @State private var popupWindow = PopupWindowReference()
    private var theme: RoomTheme { model.preferences.appearance.palette }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.menuBarShowsRoom {
                    roomPanel
                } else {
                    VideoFocusScene(model: model, presentation: .menuBar,
                                    showRoom: { model.menuBarShowsRoom = true })
                }
            }.frame(height: Self.contentSize.height)
            navigation
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .background(MenuBarWindowAppearance(target: popupWindow))
        .environment(\.roomTheme, model.preferences.appearance.palette)
        .preferredColorScheme(.dark)
        .onAppear { model.sync.refreshIfNeeded() }
    }

    private var roomPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Your room").font(.room(size: 14, weight: .medium))
                Spacer(minLength: 0)
                OverlayIconButton(symbol: "headphones", label: "Show music and timer", action: { model.menuBarShowsRoom = false })
                    .accessibilityIdentifier("menu-bar-room-toggle")
                Menu {
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

    private var navigation: some View {
        HStack(spacing: 0) {
            Button { show(.sessions) } label: {
                Label("Open Lofitime", systemImage: "arrow.up.right.square")
                    .frame(height: 44).contentShape(Rectangle())
            }.foregroundStyle(theme.accent).accessibilityIdentifier("menu-bar-open-app")
            Spacer(minLength: 8)
            Button { show(.statistics) } label: {
                Text("Stats").padding(.horizontal, 7).frame(height: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("menu-bar-stats").padding(.trailing, 7)
            Button { show(.settings) } label: {
                Text("Settings").frame(height: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("menu-bar-settings")
        }.buttonStyle(.plain).font(.room(size: 11, weight: .medium))
            .foregroundStyle(theme.text).padding(.horizontal, 16).frame(height: 44)
            .background(theme.sidebar)
            .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func show(_ section: StudioSection) {
        model.section = section
        popupWindow.window?.orderOut(nil)
        AppDelegate.openStudio?()
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

@MainActor private final class PopupWindowReference {
    weak var window: NSWindow?
}

private struct MenuBarWindowAppearance: NSViewRepresentable {
    let target: PopupWindowReference
    func makeNSView(context: Context) -> WindowAppearanceView { WindowAppearanceView() }
    func updateNSView(_ nsView: WindowAppearanceView, context: Context) {
        nsView.captureWindow = { target.window = $0 }
        nsView.applyAppearance()
    }

    final class WindowAppearanceView: NSView {
        var captureWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }

        func applyAppearance() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                self?.captureWindow?(window)
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
