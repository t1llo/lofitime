import LofiMenCore
import SwiftUI

struct StudyRoomView: View {
    @Environment(\.roomTheme) private var theme
    let growth: FocusRoom
    @Binding var showsStats: Bool
    var desktop: AnyView?
    @State private var camera = RoomCameraState()
    @State private var showsGrowth = false

    init(growth: FocusRoom, showsStats: Binding<Bool> = .constant(false), desktop: AnyView? = nil) {
        self.growth = growth
        _showsStats = showsStats
        self.desktop = desktop
    }

    var body: some View {
        VStack(spacing: 0) {
            if !showsStats {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(focusTime(growth.recentDuration)) focused").font(.room(size: 13, weight: .medium))
                    Text("Over the last 7 days").font(.room(size: 11)).foregroundStyle(theme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 15)
            }
            StudyRoomScene(growth: growth, theme: theme, camera: $camera, showsStats: showsStats, desktop: desktop)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity).clipped()
            if !showsStats { growthFooter }
        }.roomCard()
    }

    private var growthFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let next = growth.nextAddition {
                    Text("Next: \(next.title)").lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(focusTime(ceil(next.minutes - growth.minutes) * 60)) to unlock").foregroundStyle(theme.muted).lineLimit(1)
                } else {
                    Text("All room additions unlocked")
                    Spacer(minLength: 0)
                }
                Button { showsGrowth.toggle() } label: { Image(systemName: "info.circle").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).accessibilityLabel("How your room grows")
                    .popover(isPresented: $showsGrowth) { growthGuide }
            }.font(.room(size: 11)).foregroundStyle(theme.secondary)
            GeometryReader { proxy in
                Capsule().fill(theme.line)
                Capsule().fill(theme.accent).frame(width: proxy.size.width * growth.progressToNext)
            }.frame(height: 3).accessibilityLabel("Progress to the next room addition")
                .accessibilityValue("\(Int(growth.progressToNext * 100)) percent")
            Text("Scroll to zoom · Drag to move · Option-drag to tilt · Double-click to reset")
                .font(.room(size: 9)).foregroundStyle(theme.muted).frame(maxWidth: .infinity).padding(.top, 3)
        }.padding(.horizontal, 16).padding(.bottom, 13)
    }

    private var growthGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How your room grows").font(.room(size: 16, weight: .medium))
            Text("Focus sessions from the last 7 days add plants, books, lighting, and furniture to your room.")
            Text("Sessions count fully for 3 days, then gradually fade. After a week without focus, the room returns to its basic furniture. Your session history and totals are always saved.").foregroundStyle(theme.secondary)
            ForEach(RoomAddition.all) { addition in
                HStack {
                    Image(systemName: growth.minutes >= addition.minutes ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(growth.minutes >= addition.minutes ? theme.activity : theme.muted)
                    Text(addition.title)
                    Spacer()
                    Text(focusTime(addition.minutes * 60)).foregroundStyle(theme.muted)
                }
            }
            Text("Books keep filling the shelves and leaves grow between milestones.").foregroundStyle(theme.muted)
        }.font(.room(size: 11)).fixedSize(horizontal: false, vertical: true)
            .padding(20).frame(width: 345).foregroundStyle(theme.text).background(theme.surface)
    }
}

func focusTime(_ seconds: TimeInterval) -> String {
    guard seconds > 0 else { return "0m" }
    if seconds < 60 { return "<1m" }
    return SessionDuration.summary(floor(seconds / 60) * 60)
}
