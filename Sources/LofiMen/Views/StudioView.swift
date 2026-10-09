import LofiMenCore
import SwiftUI

struct StudioView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var theme: RoomTheme { model.preferences.appearance.palette }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 144)
            Rectangle().fill(theme.line).frame(width: 1)
            Group {
                if model.section == .sessions {
                    SessionsView(model: model)
                        .padding(.top, 28)
                } else {
                    ScrollView {
                        PreferencesView(model: model).padding(20).padding(.top, 20)
                    }.scrollIndicators(.hidden)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(.room(size: 12)).foregroundStyle(theme.text)
        .background(theme.background).tint(theme.accent)
        .environment(\.roomTheme, theme).preferredColorScheme(.dark)
        .frame(minWidth: 660, minHeight: 500)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            AppDelegate.openStudio = { openWindow(id: "studio") }
            applyCompactWindowSize()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandMark(size: 24)
                Text("lofitime").font(.room(size: 16, weight: .medium)).tracking(-0.5)
            }.padding(.horizontal, 4).padding(.top, 51).padding(.bottom, 34)

            navigationItem(.sessions)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text("TODAY").font(.room(size: 8, weight: .medium)).tracking(1.2)
                    .foregroundStyle(theme.muted)
                Text(SessionDuration.summary(model.todayDuration))
                    .font(.room(size: 24, weight: .light)).foregroundStyle(theme.text)
                Text("\(model.todayRecords.count) \(model.todayRecords.count == 1 ? "session" : "sessions") completed")
                    .font(.room(size: 9)).foregroundStyle(theme.muted)
            }.padding(.horizontal, 10).padding(.bottom, 22)

            Rectangle().fill(theme.line).frame(height: 1).padding(.horizontal, 8).padding(.bottom, 12)
            navigationItem(.settings).padding(.bottom, 15)
        }.padding(.horizontal, 12).background(theme.sidebar)
    }

    private func navigationItem(_ section: StudioSection) -> some View {
        Button { model.section = section } label: {
            HStack(spacing: 9) {
                Image(systemName: section.symbol).font(.system(size: 12)).frame(width: 16)
                Text(section.rawValue).font(.room(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: 35)
                .foregroundStyle(model.section == section ? theme.accent : theme.muted)
                .background(model.section == section ? theme.accent.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityAddTraits(model.section == section ? .isSelected : [])
            .accessibilityIdentifier("navigation-\(section.rawValue)")
    }

    private func applyCompactWindowSize() {
        guard !DebugTools.requested, !UserDefaults.standard.bool(forKey: "compactLayout.v3") else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.title == "Lofitime" }) else { return }
            window.setContentSize(NSSize(width: 700, height: 540))
            window.center()
            UserDefaults.standard.set(true, forKey: "compactLayout.v3")
        }
    }
}
