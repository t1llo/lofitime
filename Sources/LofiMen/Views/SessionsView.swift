import LofiMenCore
import SwiftUI

struct SessionsView: View {
    @Environment(\.roomTheme) private var theme
    @State private var selectedDay: Date?
    @State private var weekOffset = 0
    var model: AppModel

    private var activity: FocusActivity {
        weekOffset == 0 ? model.activity : FocusActivity(records: model.records, through: model.activity.endDate, weekOffset: weekOffset)
    }

    private var canGoBack: Bool { model.records.contains { $0.finishedAt < activity.startDate } }

    private var displayedRecords: [SessionRecord] {
        if let selectedDay {
            return model.records.filter {
                Calendar.current.isDate($0.finishedAt, inSameDayAs: selectedDay) && $0.finishedAt <= model.now
            }.sorted { $0.finishedAt > $1.finishedAt }
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your focus forest").font(.room(size: 21, weight: .medium))
                    Text("A little focus. A little more life.")
                        .font(.room(size: 11)).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    IconButton(symbol: "chevron.left", label: "Previous three weeks", size: 26) { weekOffset -= 3 }
                        .disabled(!canGoBack).opacity(canGoBack ? 1 : 0.35)
                        .accessibilityIdentifier("activity-previous")
                    Button("Today") { weekOffset = 0 }
                        .buttonStyle(.plain).font(.room(size: 10, weight: .medium)).foregroundStyle(theme.accent)
                        .accessibilityIdentifier("activity-today")
                    IconButton(symbol: "chevron.right", label: "Next three weeks", size: 26) { weekOffset = min(0, weekOffset + 3) }
                        .disabled(weekOffset == 0).opacity(weekOffset == 0 ? 0.35 : 1)
                        .accessibilityIdentifier("activity-next")
                }
            }
            HStack(spacing: 0) {
                metric(SessionDuration.summary(activity.totalDuration), label: "focused")
                metric("\(activity.totalSessions)", label: "sessions")
                metric("\(activity.activeDays)", label: "active days")
                Spacer(minLength: 0)
                Text("\(activity.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(activity.endDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.room(size: 9)).foregroundStyle(theme.muted).multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
            }.padding(12).roomCard()

            FocusGarden(activity: activity, selectedDay: $selectedDay)
                .overlay(alignment: .bottom) {
                    if selectedDay != nil { sessionDetails.padding(10) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line))
            Text(activity.totalSessions == 0
                 ? "Complete a focus session to plant your first shoots."
                 : "Each clearing is a day. Hover to explore · Click for sessions")
                .font(.room(size: 10)).foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
        }.padding(18)
            .onChange(of: weekOffset) { _, _ in selectedDay = nil }
            .onChange(of: model.activity.endDate) { _, _ in selectedDay = nil }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.room(size: 15, weight: .medium)).monospacedDigit().foregroundStyle(theme.text)
            Text(label).font(.room(size: 9)).foregroundStyle(theme.muted)
        }.frame(minWidth: 75, alignment: .leading).padding(.trailing, 10)
            .accessibilityElement(children: .combine)
    }

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDay.map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? "Sessions")
                        .font(.room(size: 12, weight: .medium))
                        .accessibilityIdentifier("activity-session-heading")
                    if let day = activity.weeks.flatMap({ $0 }).first(where: { $0.date == selectedDay }) {
                        Text("\(day.duration > 0 ? day.habitat.title : day.growthTitle) · \(SessionDuration.summary(day.duration)) focused")
                            .font(.room(size: 10)).foregroundStyle(theme.muted)
                    }
                }
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
                            }.padding(.vertical, 9).padding(.horizontal, 4).accessibilityElement(children: .combine)
                                .accessibilityIdentifier("session-record-\(record.id)")
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: min(CGFloat(displayedRecords.count) * 49, 100))
            }
        }.roomCard(padding: 14)
    }
}
