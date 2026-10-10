import LofiMenCore
import SwiftUI

struct SessionsView: View {
    @Environment(\.roomTheme) private var theme
    var model: AppModel

    private var showsStats: Binding<Bool> {
        Binding(get: { model.section == .statistics }, set: { model.section = $0 ? .statistics : .sessions })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showsStats.wrappedValue ? "Your focus stats" : "Your room").font(.room(size: 23, weight: .medium))
                    Text(showsStats.wrappedValue ? "See your progress and explore past sessions." : "Build your room with every focus session.")
                        .font(.room(size: 11)).foregroundStyle(theme.muted)
                }
                Spacer()
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                StudyRoomView(growth: FocusRoom(records: model.records, through: max(context.date, model.activity.updatedAt)),
                              showsStats: showsStats,
                              desktop: AnyView(DeskStatsView(model: model).environment(\.roomTheme, theme)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(18)
            .onAppear { model.tick() }
    }
}
