import LofiMenCore
import SwiftUI

struct SessionsView: View {
    @Environment(\.roomTheme) private var theme
    @State private var showsStats = false
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your little study").font(.room(size: 23, weight: .medium))
                    Text("Time well spent, a space well loved.").font(.room(size: 11)).foregroundStyle(theme.muted)
                }
                Spacer()
                Image(systemName: "house").font(.system(size: 23, weight: .light)).foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                StudyRoomView(growth: FocusRoom(records: model.records, through: max(context.date, model.activity.updatedAt)),
                              showsStats: $showsStats,
                              desktop: AnyView(DeskStatsView(model: model).environment(\.roomTheme, theme)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(18)
            .onAppear { model.tick() }
    }
}
