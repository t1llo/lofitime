import AppKit
import SwiftUI

struct MenuBarView: View {
    static let size = CGSize(width: 320, height: 360)
    static let cornerRadius: CGFloat = 20
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VideoFocusScene(model: model, presentation: .menuBar, openStudio: {
            model.section = .studio
            openWindow(id: "studio")
            NSApp.activate(ignoringOtherApps: true)
        })
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .background(MenuBarWindowAppearance())
        .environment(\.roomTheme, model.preferences.appearance.palette)
        .preferredColorScheme(.dark)
    }
}

private struct MenuBarWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowAppearanceView { WindowAppearanceView() }
    func updateNSView(_ nsView: WindowAppearanceView, context: Context) { nsView.applyAppearance() }

    final class WindowAppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }

        func applyAppearance() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                window.isOpaque = false
                window.backgroundColor = .clear
                // The window's material and native hosting frame sit outside the
                // SwiftUI clip. Round both so no square outer corners remain.
                for view in [window.contentView, window.contentView?.superview].compactMap({ $0 }) {
                    view.wantsLayer = true
                    view.layer?.cornerRadius = MenuBarView.cornerRadius
                    view.layer?.cornerCurve = .continuous
                    view.layer?.masksToBounds = true
                }
                window.invalidateShadow()
            }
        }
    }
}
