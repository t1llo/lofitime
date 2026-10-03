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
        return []
    }

    var body: some View {
        FocusGarden(activity: model.activity, selectedDay: $selectedDay)
            .overlay(alignment: .bottom) {
                if selectedDay != nil {
                    sessionDetails.padding(16)
                }
            }
    }

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDay.map { $0.formatted(.dateTime.month(.wide).day().year()) }
                     ?? "Sessions")
                    .font(.room(size: 13, weight: .medium))
                    .accessibilityIdentifier("activity-session-heading")
                Spacer()
                Button("Close") { selectedDay = nil }.buttonStyle(.plain)
                    .font(.room(size: 11)).foregroundStyle(theme.accent)
                    .accessibilityIdentifier("activity-close-details")
            }
            if displayedRecords.isEmpty {
                Text("No completed sessions on this day.")
                    .font(.room(size: 12)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(displayedRecords.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Rectangle().fill(theme.line).frame(height: 1) }
                            HStack(spacing: 10) {
                                Circle().fill(theme.activity).frame(width: 5, height: 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.intention).font(.room(size: 12)).lineLimit(1)
                                    Text(record.finishedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.room(size: 9)).foregroundStyle(theme.muted)
                                }
                                Spacer()
                                Text(SessionDuration.summary(record.duration))
                                    .font(.room(size: 11)).monospacedDigit()
                                    .foregroundStyle(theme.secondary).frame(minWidth: 65, alignment: .trailing)
                            }.padding(15).accessibilityElement(children: .combine)
                                .accessibilityIdentifier("session-record-\(record.id)")
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: min(CGFloat(displayedRecords.count) * 65, 170))
            }
        }.roomCard(padding: 14)
    }
}
