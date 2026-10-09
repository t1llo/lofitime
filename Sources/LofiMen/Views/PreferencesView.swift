import LofiMenCore
import SwiftUI

struct PreferencesView: View {
    @Environment(\.roomTheme) private var theme
    @Bindable var model: AppModel
    @ObservedObject private var updater = UpdateService.shared
    @ObservedObject private var login = LoginService.shared
    @State private var showingVideoQuality = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings").font(.room(size: 21, weight: .medium))

            VStack(alignment: .leading, spacing: 14) {
                Text("Appearance").font(.room(size: 13, weight: .medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 195), spacing: 10)], spacing: 10) {
                    ForEach(AppAppearance.allCases) { appearance in
                        themeChoice(appearance)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).roomCard(padding: 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("Video quality").font(.room(size: 13, weight: .medium))
                Button("Choose YouTube quality…") {
                    showingVideoQuality = true
                }.accessibilityIdentifier("video-quality-settings")
                Text("Choose a resolution in YouTube's gear menu → Quality. Available resolutions and how long the choice is remembered are managed by YouTube, not Lofitime.")
                    .font(.room(size: 10)).foregroundStyle(theme.muted)
            }.roomCard(padding: 16)

            VStack(alignment: .leading, spacing: 18) {
                Text("Timer defaults").font(.room(size: 13, weight: .medium))
                HStack(spacing: 16) {
                    durationField("Focus", value: $model.preferences.timer.focusMinutes)
                    durationField("Short break", value: $model.preferences.timer.shortBreakMinutes)
                    durationField("Long break", value: $model.preferences.timer.longBreakMinutes)
                }
                Rectangle().fill(theme.line).frame(height: 1)
                HStack {
                    Text("Long break after").font(.room(size: 12))
                    Spacer()
                    IntegerField(label: "Sessions before a long break", value: $model.preferences.timer.sessionsBeforeLongBreak,
                                 range: 2...8, unit: "sessions")
                }
                Text("Type a value and press Return. You can also type minutes or mm:ss directly into the countdown.")
                    .font(.room(size: 10)).foregroundStyle(theme.muted)
            }.roomCard(padding: 16)

            VStack(alignment: .leading, spacing: 18) {
                Text("Behavior").font(.room(size: 13, weight: .medium))
                preferenceToggle("Launch at login", value: Binding(get: { login.enabled }, set: login.setEnabled))
                if login.status == .requiresApproval {
                    Text("Allow Lofitime in System Settings → General → Login Items.")
                        .font(.room(size: 11)).foregroundStyle(theme.amber)
                    Button("Open Login Items", action: login.openSettings)
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                }
                if let error = login.error {
                    Text(error).font(.room(size: 11)).foregroundStyle(theme.amber)
                }
                preferenceToggle("Start music with focus", value: $model.preferences.startMusicWithFocus)
                preferenceToggle("Automatically start breaks", value: $model.preferences.autoStartBreaks)
                preferenceToggle("Automatically start the next focus session", value: $model.preferences.autoStartFocus)
                Rectangle().fill(theme.line).frame(height: 1)
                preferenceToggle("Play a chime when a session ends", value: $model.preferences.completionSound)
                preferenceToggle("Session notifications", value: Binding(
                    get: { model.preferences.notifications }, set: { model.setNotifications($0) }))
                if let error = model.notificationError {
                    Text(error).font(.room(size: 11)).foregroundStyle(theme.amber)
                }
                if model.notificationPermissionDenied {
                    Button("Open Notification Settings", action: model.openNotificationSettings)
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                }
                preferenceToggle("Show countdown in the menu bar", value: $model.preferences.showMenuBarCountdown)
            }.roomCard(padding: 16)

            VStack(alignment: .leading, spacing: 18) {
                Text("Software updates").font(.room(size: 13, weight: .medium))
                preferenceToggle("Check for updates automatically", value: Binding(
                    get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                preferenceToggle("Download and install updates automatically", value: Binding(
                    get: { updater.automaticDownloads }, set: updater.setAutomaticDownloads))
                CheckForUpdatesButton()
                Text("Updates are checked hourly and installed when the app quits. You can also choose to install and relaunch from the update prompt.")
                    .font(.room(size: 10)).foregroundStyle(theme.muted)
            }.roomCard(padding: 16)
        }
        .task {
            login.refresh()
            await model.refreshNotificationAuthorization()
        }
        .sheet(isPresented: $showingVideoQuality) {
            VideoQualityView(player: model.player)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
            Task { await model.refreshNotificationAuthorization() }
        }
    }

    private func themeChoice(_ appearance: AppAppearance) -> some View {
        let palette = appearance.palette
        let selected = model.preferences.appearance == appearance
        return Button { model.preferences.appearance = appearance } label: {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(Array([palette.accent, palette.text, palette.activity].enumerated()), id: \.offset) { _, color in
                        Capsule().fill(color).frame(width: 5, height: 22)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(appearance.title).font(.room(size: 12, weight: .medium))
                    Text(appearance.subtitle).font(.room(size: 9)).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13)).foregroundStyle(selected ? palette.accent : palette.muted)
            }.padding(.horizontal, 13).frame(maxWidth: .infinity).frame(height: 62).foregroundStyle(palette.text)
                .background(palette.background, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? palette.accent : palette.line))
        }.buttonStyle(.plain).accessibilityLabel(appearance.title)
            .accessibilityIdentifier("theme-\(appearance.rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func preferenceToggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.room(size: 12)).foregroundStyle(theme.secondary)
            Spacer()
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func durationField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.room(size: 11)).foregroundStyle(theme.secondary)
            IntegerField(label: "\(title) minutes", value: value, range: 1...180, unit: "min")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VideoQualityView: View {
    let player: RadioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YouTube video quality").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("video-quality-done")
            }
            Text("Start playback if needed, then use the gear → Quality to choose a resolution. The same player supplies the studio and menu-bar previews.")
                .font(.caption).foregroundStyle(.secondary)
            RadioWebView(player: player, presentation: .quality, fillsBounds: false)
                .frame(width: 560, height: 315)
            if let error = player.error {
                Text(error).font(.caption)
                Button("Retry") { player.retry() }
            }
        }
        .padding(20)
        .onAppear { if !player.hasLoaded { player.play() } }
    }
}

struct IntegerField: View {
    @Environment(\.roomTheme) private var theme
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var compact = false
    @State private var input = ""
    @FocusState private var focused: Bool

    private var valid: Bool { Int(input).map { range.contains($0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(label, text: $input).textFieldStyle(.plain)
                    .font(.room(size: compact ? 16 : 19)).monospacedDigit()
                    .multilineTextAlignment(.center).frame(width: compact ? 46 : 54, height: compact ? 28 : 34)
                    .background(theme.background, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? theme.accent : theme.line))
                    .focused($focused).onSubmit { commit(); focused = false }.accessibilityLabel(label)
                Text(unit).font(.room(size: compact ? 10 : 11)).foregroundStyle(theme.muted)
            }
            if !input.isEmpty && !valid {
                Text("Use \(range.lowerBound)–\(range.upperBound)").font(.room(size: 9)).foregroundStyle(theme.amber)
            }
        }
        .onAppear { input = String(value) }
        .onChange(of: value) { _, value in if !focused { input = String(value) } }
        .onChange(of: focused) { _, focused in if !focused { commit() } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        if let number = Int(input), range.contains(number), number != value { value = number }
        input = String(value)
    }
}
