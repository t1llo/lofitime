import LofiMenCore
import SwiftUI

struct SessionsView: View {
    @Environment(\.roomTheme) private var theme
    @State private var selectedDay: Date?
    var model: AppModel

    private var displayedRecords: [SessionRecord] {
        if let selectedDay {
            return model.records.filter { Calendar.current.isDate($0.finishedAt, inSameDayAs: selectedDay) }
        }
        return Array(model.records.prefix(15))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.room(size: 21, weight: .medium))
                Spacer()
                Text("Last \(FocusActivity.historyDays) days").font(.room(size: 11)).foregroundStyle(theme.muted)
            }

            FocusGarden(activity: model.activity, selectedDay: $selectedDay)

            HStack {
                Text(selectedDay.map { $0.formatted(.dateTime.month(.wide).day().year()) }
                     ?? "Recent sessions")
                    .font(.room(size: 13, weight: .medium))
                    .accessibilityIdentifier("activity-session-heading")
                Spacer()
                if selectedDay != nil {
                    Button("Show all") { selectedDay = nil }.buttonStyle(.plain)
                        .font(.room(size: 11)).foregroundStyle(theme.accent)
                        .accessibilityIdentifier("activity-show-all")
                }
            }
            if displayedRecords.isEmpty {
                Text(selectedDay == nil ? "Complete a focus session to grow your first flower." : "No completed sessions on this day.")
                    .font(.room(size: 12)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 25).roomCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedRecords.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Rectangle().fill(theme.line).frame(height: 1) }
                        HStack(spacing: 10) {
                            Circle().fill(theme.activity).frame(width: 5, height: 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.intention).font(.room(size: 12)).lineLimit(1)
                                Text(record.finishedAt.formatted(date: selectedDay == nil ? .abbreviated : .omitted, time: .shortened))
                                    .font(.room(size: 9)).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Text(SessionDuration.summary(record.duration))
                                .font(.room(size: 11)).monospacedDigit()
                                .foregroundStyle(theme.secondary).frame(minWidth: 65, alignment: .trailing)
                        }.padding(15).accessibilityElement(children: .combine)
                            .accessibilityIdentifier("session-record-\(record.id)")
                    }
                }.roomCard()
            }
        }
    }
}
