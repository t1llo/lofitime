import AppKit
import LofiMenCore
import SwiftUI
import UserNotifications

@main
struct LofiMenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(nsImage: MenuBarLabel.image(
                countdown: model.preferences.showMenuBarCountdown && model.timer.status != .ready ? model.remainingText : nil,
                paused: model.timer.status == .paused))
                .accessibilityLabel("Lofitime" + (model.timer.status == .ready ? "" : ": \(model.remainingText)"))
        }
        .menuBarExtraStyle(.window)
        .commands { RoomCommands(model: model) }
    }
}

enum MenuBarLabel {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let countdownWidth = ceil(("00:00" as NSString).size(withAttributes: [.font: font]).width) + 2
    static let activeSize = NSSize(width: 22 + countdownWidth, height: 18)

    static func image(countdown: String?, paused: Bool) -> NSImage {
        let size = countdown == nil ? NSSize(width: 18, height: 18) : activeSize
        let image = NSImage(size: size, flipped: false) { bounds in
            if countdown != nil && paused {
                NSColor.black.setFill()
                NSRect(x: 5, y: 4, width: 3, height: 10).fill()
                NSRect(x: 11, y: 4, width: 3, height: 10).fill()
            } else {
                AppResources.menuBarIcon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            }
            if let countdown {
                let naturalWidth = (countdown as NSString).size(withAttributes: [.font: font]).width
                let fittedFont = NSFont.monospacedDigitSystemFont(ofSize: 13 * min(1, countdownWidth / max(1, naturalWidth)), weight: .regular)
                let text = NSAttributedString(string: countdown, attributes: [.font: fittedFont, .foregroundColor: NSColor.black])
                text.draw(at: NSPoint(x: 22, y: (bounds.height - text.size().height) / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var openStudio: (() -> Void)?
    let model = DebugTools.makeModel()
    private lazy var studio = StudioWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        Self.openStudio = { [weak self] in self?.studio.show() }
        DebugTools.prepareLaunch()
        LoginService.shared.start()
        UpdateService.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openStudio?()
        return false
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

/// Own the optional window explicitly so launch-at-login never opens it or adds a Dock tile.
@MainActor
private final class StudioWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Lofitime"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 660, height: 500)
            window.contentView = NSHostingView(rootView: StudioView(model: model)
                .task { DebugTools.runIfRequested(model: self.model) })
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("LofitimeStudio")
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.sync.refreshIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct RoomCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton()
        }
        CommandGroup(replacing: .newItem) {
            Button("Open My Room") { show(.sessions) }.keyboardShortcut("1", modifiers: .command)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { show(.settings) }.keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Focus") {
            Button(model.timerActionTitle) { model.toggleTimer() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Reset Session") { model.resetTimer() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Skip to Next Session") { model.skipSession() }
            Divider()
            Button(model.player.isPlaying ? "Pause Music" : "Play Music") { model.player.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("View Stats") { show(.statistics) }.keyboardShortcut("2", modifiers: .command)
        }
    }

    private func show(_ section: StudioSection) {
        model.section = section
        AppDelegate.openStudio?()
    }
}
