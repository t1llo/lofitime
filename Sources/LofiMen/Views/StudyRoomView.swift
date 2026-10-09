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
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showsStats ? "At your desk" : growth.title).font(.room(size: 14, weight: .medium))
                    Text(showsStats ? "Your focus story, on your desktop." : "\(focusTime(growth.recentDuration)) of focus over the last 7 days")
                        .font(.room(size: 10)).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 5)
                if desktop != nil {
                    Button { showsStats.toggle() } label: {
                        Label(showsStats ? "Back to room" : "View stats", systemImage: showsStats ? "arrow.uturn.backward" : "chart.bar.xaxis")
                            .font(.room(size: 11, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 8)
                            .background(theme.accent.opacity(0.12), in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(theme.accent).accessibilityIdentifier("activity-view-stats")
                }
            }.padding(.horizontal, 16).padding(.top, 15)
            StudyRoomScene(growth: growth, theme: theme, camera: $camera, showsStats: showsStats, desktop: desktop)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity).clipped()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: growth.nextAddition == nil ? "sparkles" : "leaf").foregroundStyle(theme.activity)
                    if let next = growth.nextAddition {
                        Text("Next: \(next.title)").lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(focusTime(ceil(next.minutes - growth.minutes) * 60)) to grow").foregroundStyle(theme.muted).lineLimit(1)
                    } else {
                        Text("A soft place to land, made by your focus.")
                        Spacer(minLength: 0)
                    }
                    Button { showsGrowth.toggle() } label: { Image(systemName: "info.circle").frame(width: 22, height: 22) }
                        .buttonStyle(.plain).foregroundStyle(theme.muted).accessibilityLabel("How your room grows")
                        .popover(isPresented: $showsGrowth) { growthGuide }
                }.font(.room(size: 10))
                GeometryReader { proxy in
                    Capsule().fill(theme.line)
                    Capsule().fill(theme.activity).frame(width: proxy.size.width * growth.progressToNext)
                }.frame(height: 3).accessibilityLabel("Progress to the next room addition")
                    .accessibilityValue("\(Int(growth.progressToNext * 100)) percent")
                Text(showsStats ? "Explore weeks, months, and individual days on the screen." : "Scroll or pinch to zoom · Drag to explore · Double-click to reset")
                    .font(.room(size: 9)).foregroundStyle(theme.muted).frame(maxWidth: .infinity).padding(.top, 3)
            }.padding(.horizontal, 16).padding(.bottom, 13)
        }.roomCard()
    }

    private var growthGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Small sessions. A softer space.").font(.room(size: 16, weight: .medium))
            Text("Completed focus sessions nourish one shared room over the last 7 days. Plants grow, flowers open, and cozy things find a home here.")
            Text("Each session's warmth starts to fade after 3 days. After a week without focus, the desk, computer, window, and bed remain. Your time and session history are always kept.").foregroundStyle(theme.secondary)
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
