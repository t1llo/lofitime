import AppKit
import LofiMenCore
import SwiftUI
import UserNotifications

@main
struct LofiMenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = DebugTools.makeModel()

    var body: some Scene {
        Window("Lofitime", id: "studio") {
            StudioView(model: model)
                .task { DebugTools.runIfRequested(model: model) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 540)
        .defaultPosition(.center)
        .commands { RoomCommands(model: model) }

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(nsImage: AppResources.menuBarIcon)
                .accessibilityLabel("Lofitime")
            if model.preferences.showMenuBarCountdown && model.timer.status != .ready {
                Text(model.remainingText).font(.room(size: 13)).monospacedDigit()
                if model.timer.status == .paused { Image(systemName: "pause.fill") }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var openStudio: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        DebugTools.prepareLaunch()
        LoginService.shared.start()
        UpdateService.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.openStudio?() }
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

private struct RoomCommands: Commands {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton()
        }
        CommandGroup(replacing: .newItem) {
            Button("Open My Studio") { show(.studio) }.keyboardShortcut("1", modifiers: .command)
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
            Button("Activity") { show(.sessions) }.keyboardShortcut("2", modifiers: .command)
        }
    }

    private func show(_ section: StudioSection) {
        model.section = section
        openWindow(id: "studio")
        NSApp.activate(ignoringOtherApps: true)
    }
}
