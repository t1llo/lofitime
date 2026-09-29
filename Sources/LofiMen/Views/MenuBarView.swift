import SwiftUI

struct MenuBarView: View {
    static let size = CGSize(width: 320, height: 360)
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VideoFocusScene(model: model, presentation: .menuBar, openStudio: {
            model.section = .studio
            openWindow(id: "studio")
            NSApp.activate(ignoringOtherApps: true)
        })
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .environment(\.roomTheme, model.preferences.appearance.palette)
        .preferredColorScheme(.dark)
    }
}
