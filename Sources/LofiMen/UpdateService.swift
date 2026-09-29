import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var started = false

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: DispatchQueue.main).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: DispatchQueue.main).assign(to: &$automaticDownloads)
    }

    func start() {
        guard !started, !DebugTools.requested, Bundle.main.bundleURL.pathExtension == "app" else { return }
        started = true
        controller.startUpdater()
    }

    func check() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { controller.updater.automaticallyDownloadsUpdates = enabled }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = UpdateService.shared
    var body: some View {
        Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck)
    }
}
