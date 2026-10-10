import LofiMenSync
import SwiftUI

struct GitHubSyncView: View {
    @Environment(\.roomTheme) private var theme
    @Bindable var sync: GitHubSyncService
    @State private var showingSetup = false
    @State private var copiedCommand = false
    @State private var setup: Setup?
    @State private var repositoryLink = ""
    @State private var copiedLink = false

    private enum Setup { case create, connect }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sync across Macs").font(.room(size: 13, weight: .medium))
                Spacer()
                if sync.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Syncing with GitHub") }
            }
            Text("Keep your focus history and growing room together with a private GitHub repository.")
                .font(.room(size: 11)).foregroundStyle(theme.secondary)

            if let connection = sync.connection {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(theme.muted)
                    if let url = URL(string: "https://github.com/\(connection.repository)") {
                        Link(connection.repository, destination: url).foregroundStyle(theme.accent)
                    }
                }.font(.room(size: 12))
                if sync.isBusy {
                    Text("Merging focus sessions…").font(.room(size: 11)).foregroundStyle(theme.muted)
                } else if let lastSynced = sync.lastSyncedAt {
                    Text("Last synced \(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                        .font(.room(size: 11)).foregroundStyle(theme.muted)
                } else {
                    Text("Waiting for the first sync").font(.room(size: 11)).foregroundStyle(theme.muted)
                }
                HStack(spacing: 12) {
                    Button("Sync now", action: sync.syncNow).disabled(sync.isBusy)
                        .accessibilityIdentifier("github-sync-now")
                    Button(copiedLink ? "Copied" : "Copy repository link") {
                        copy("https://github.com/\(connection.repository)")
                        copiedLink = true
                    }
                    Button("Disconnect", action: sync.disconnect).accessibilityIdentifier("github-sync-disconnect")
                }
                Text("Syncs at launch, when you return, after each focus session, and every five minutes. Offline sessions sync when you reconnect. Disconnecting keeps your history and repository.")
                    .font(.room(size: 10)).foregroundStyle(theme.muted)
            } else {
                HStack(spacing: 10) {
                    Button("Create a new sync") { setup = .create }
                        .buttonStyle(CalmButtonStyle(prominent: setup == .create, compact: true, expands: false))
                        .accessibilityIdentifier("github-sync-create-choice")
                    Button("Connect to sync") { setup = .connect }
                        .buttonStyle(CalmButtonStyle(prominent: setup == .connect, compact: true, expands: false))
                        .accessibilityIdentifier("github-sync-connect-choice")
                }.disabled(sync.isBusy)
                if let setup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(setup == .create ? "New repository name" : "Repository link")
                            .font(.room(size: 11)).foregroundStyle(theme.secondary)
                        TextField(setup == .create ? "lofitime-sync" : "https://github.com/username/lofitime-sync",
                                  text: setup == .create ? $sync.repositoryName : $repositoryLink)
                            .textFieldStyle(.plain).font(.room(size: 12)).padding(10)
                            .background(theme.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line))
                            .disabled(sync.isBusy).accessibilityIdentifier("github-sync-repository")
                    }
                    HStack(spacing: 12) {
                        Button(sync.isBusy ? "Connecting…" : setup == .create ? "Create private sync" : "Connect") {
                            if setup == .create { sync.create() }
                            else { sync.connect(repository: repositoryLink) }
                        }.disabled(sync.isBusy || (setup == .create ? sync.repositoryName : repositoryLink)
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("github-sync-connect")
                        if sync.isBusy { Button("Cancel", action: sync.disconnect) }
                    }
                }
                Text("Create a private repository on your first Mac, then paste its link on your other Macs. Uses your GitHub CLI login. Completed session times, durations, and intentions are synced.")
                    .font(.room(size: 10)).foregroundStyle(theme.muted)
            }

            if let error = sync.error {
                Text(error).font(.room(size: 11)).foregroundStyle(theme.amber).textSelection(.enabled)
                    .accessibilityIdentifier("github-sync-error")
            }

            DisclosureGroup("GitHub CLI setup", isExpanded: $showingSetup) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install GitHub CLI, then run this command in Terminal on each Mac:")
                        .font(.room(size: 11)).foregroundStyle(theme.secondary)
                    Text("gh auth login --hostname github.com --web --scopes repo")
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    HStack(spacing: 12) {
                        Link("Get GitHub CLI", destination: URL(string: "https://cli.github.com")!)
                        Button(copiedCommand ? "Copied" : "Copy login command") {
                            copy("gh auth login --hostname github.com --web --scopes repo")
                            copiedCommand = true
                        }
                    }
                    Text("Then create or connect to sync. Lofitime uses the CLI's existing credentials; your account needs write access to the repository.")
                        .font(.room(size: 10)).foregroundStyle(theme.muted)
                }.padding(.top, 8)
            }.font(.room(size: 11))
        }.buttonStyle(CalmButtonStyle(compact: true, expands: false))
            .frame(maxWidth: .infinity, alignment: .leading).roomCard(padding: 16)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
