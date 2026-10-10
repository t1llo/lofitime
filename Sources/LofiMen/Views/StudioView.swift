import LofiMenCore
import SwiftUI

struct StudioView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var theme: RoomTheme { model.preferences.appearance.palette }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                BrandMark(size: 27)
                Text("lofitime").font(.room(size: 15, weight: .medium))
                Spacer(minLength: 16)
                ForEach(StudioSection.allCases) { section in
                    Button { model.section = section } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                    }.buttonStyle(CalmButtonStyle(prominent: model.section == section, compact: true, expands: false))
                        .accessibilityIdentifier("navigation-\(section.rawValue)")
                        .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
            }.padding(.horizontal, 20).padding(.vertical, 12).padding(.top, 28)
                .background(theme.sidebar)
            Rectangle().fill(theme.line).frame(height: 1)
            Group {
                if model.section != .settings {
                    SessionsView(model: model)
                } else {
                    ScrollView {
                        PreferencesView(model: model).padding(20)
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
            model.sync.refreshIfNeeded()
        }
    }
}
