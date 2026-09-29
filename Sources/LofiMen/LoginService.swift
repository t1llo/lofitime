import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginService: ObservableObject {
    static let shared = LoginService()
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: String?
    var enabled: Bool { status == .enabled }

    private init() {}

    func start() {
        guard !DebugTools.requested, Bundle.main.bundleURL.pathExtension == "app" else { return }
        refresh()
        // Register once; subsequent launches respect changes made in System Settings.
        guard !UserDefaults.standard.bool(forKey: "loginItem.configured") else { return }
        if status == .enabled || status == .requiresApproval {
            UserDefaults.standard.set(true, forKey: "loginItem.configured")
        } else {
            setEnabled(true)
        }
    }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        error = nil
        refresh()
        if enabled && status == .requiresApproval {
            openSettings()
            return
        }
        do {
            if enabled && status != .enabled { try SMAppService.mainApp.register() }
            else if !enabled && status != .notRegistered { try SMAppService.mainApp.unregister() }
            UserDefaults.standard.set(true, forKey: "loginItem.configured")
        } catch {
            self.error = "Couldn't update launch at login: \(error.localizedDescription)"
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
