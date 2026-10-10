import LofiMenCore
import SwiftUI

struct StudioView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var theme: RoomTheme { model.preferences.appearance.palette }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.section == .sessions {
                    SessionsView(model: model)
                } else {
                    ScrollView {
                        PreferencesView(model: model).padding(20)
                    }.scrollIndicators(.hidden)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 28)
            Rectangle().fill(theme.line).frame(height: 1)
            HStack(spacing: 16) {
                Button { model.section = .sessions } label: {
                    HStack(spacing: 8) {
                        BrandMark(size: 25)
                        Text("lofitime").font(.room(size: 14, weight: .medium))
                    }
                }.buttonStyle(.plain).accessibilityLabel("Activity")
                    .accessibilityIdentifier("navigation-Activity")
                    .help("Back to your room")
                Spacer(minLength: 4)
                Text("\(focusTime(model.todayDuration)) today · \(model.todayRecords.count) \(model.todayRecords.count == 1 ? "session" : "sessions")")
                    .font(.room(size: 11)).foregroundStyle(theme.muted)
                Button { model.section = model.section == .settings ? .sessions : .settings } label: {
                    Label("Settings", systemImage: "gearshape")
                }.buttonStyle(CalmButtonStyle(prominent: model.section == .settings, compact: true, expands: false))
                    .accessibilityIdentifier("navigation-Settings")
                    .accessibilityAddTraits(model.section == .settings ? .isSelected : [])
            }.padding(.horizontal, 20).padding(.vertical, 12).background(theme.sidebar)
        }
        .font(.room(size: 12)).foregroundStyle(theme.text)
        .background(theme.background).tint(theme.accent)
        .environment(\.roomTheme, theme).preferredColorScheme(.dark)
        .frame(minWidth: 660, minHeight: 500)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            AppDelegate.openStudio = { openWindow(id: "studio") }
            model.sync.refreshIfNeeded()
        }
    }
}
