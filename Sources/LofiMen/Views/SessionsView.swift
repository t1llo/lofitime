import LofiMenCore
import SwiftUI

struct SessionsView: View {
    @Environment(\.roomTheme) private var theme
    @State private var selectedDay: Date?
    var model: AppModel

    private var displayedRecords: [SessionRecord] {
        guard let selectedDay else { return Array(model.records.prefix(15)) }
        return model.records.filter { Calendar.current.isDate($0.finishedAt, inSameDayAs: selectedDay) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.room(size: 21, weight: .medium))
                Spacer()
                Text("Last 365 days").font(.room(size: 11)).foregroundStyle(theme.muted)
            }

            ActivityGrid(activity: model.activity, selectedDay: $selectedDay)

            HStack {
                Text(selectedDay.map { $0.formatted(.dateTime.month(.wide).day().year()) } ?? "Recent sessions")
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
                Text(selectedDay == nil ? "Complete a focus session to add your first square." : "No completed sessions on this day.")
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

struct ActivityGrid: View {
    @Environment(\.roomTheme) private var theme
    let activity: FocusActivity
    @Binding var selectedDay: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                Text("\(activity.totalSessions) \(activity.totalSessions == 1 ? "session" : "sessions")")
                Text("·").foregroundStyle(theme.muted)
                Text("\(SessionDuration.summary(activity.totalDuration)) focused")
            }.font(.room(size: 12)).foregroundStyle(theme.secondary)

            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    calendarGrid(width: max(680, geometry.size.width))
                        .frame(width: max(680, geometry.size.width), height: 132, alignment: .topLeading)
                }.defaultScrollAnchor(.trailing)
            }.frame(height: 148)

            HStack {
                Text("\(activity.activeDays) active \(activity.activeDays == 1 ? "day" : "days")")
                Spacer()
                Text("Less")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2).fill(theme.activityColor(level: level))
                        .frame(width: 10, height: 10).accessibilityHidden(true)
                }
                Text("More")
            }.font(.room(size: 10)).foregroundStyle(theme.muted)
        }.roomCard(padding: 16)
    }

    private func calendarGrid(width: CGFloat) -> some View {
        let gap: CGFloat = 3
        let labelWidth: CGFloat = 30
        let cell = (width - labelWidth - gap * CGFloat(activity.weeks.count - 1)) / CGFloat(activity.weeks.count)
        return ZStack(alignment: .topLeading) {
                    ForEach(activity.weeks.indices, id: \.self) { index in
                        if let month = monthLabel(at: index) {
                            Text(month).font(.room(size: 9)).foregroundStyle(theme.muted)
                                .frame(width: 42, alignment: .leading)
                                .offset(x: min(width - 42, labelWidth + CGFloat(index) * (cell + gap)))
                        }
                    }
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: gap) {
                            ForEach(0..<7) { row in
                                Text([1, 3, 5].contains(row) ? Calendar.current.shortWeekdaySymbols[row] : "")
                                    .font(.room(size: 8)).foregroundStyle(theme.muted)
                                    .frame(width: labelWidth, height: cell, alignment: .leading)
                            }
                        }
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(activity.weeks.indices, id: \.self) { index in
                                VStack(spacing: gap) {
                                    ForEach(activity.weeks[index]) { day in
                                        Button {
                                            selectedDay = selectedDay == day.date ? nil : day.date
                                        } label: {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(theme.activityColor(level: day.level))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .strokeBorder(selectedDay == day.date ? theme.text : .clear, lineWidth: 1.5)
                                                }
                                                .frame(width: cell, height: cell)
                                                .opacity(day.isInRange ? 1 : 0)
                                        }.buttonStyle(.plain).disabled(!day.isInRange)
                                            .help(dayDescription(day)).accessibilityLabel(dayDescription(day))
                                             .accessibilityHidden(!day.isInRange)
                                             .accessibilityAddTraits(selectedDay == day.date ? .isSelected : [])
                                             .accessibilityIdentifier("activity-day-\(day.date.timeIntervalSince1970)")
                                    }
                                }
                            }
                        }
                    }.offset(y: 21)
        }
    }

    private func monthLabel(at index: Int) -> String? {
        let week = activity.weeks[index]
        if let first = week.first(where: { Calendar.current.component(.day, from: $0.date) == 1 && $0.isInRange }) {
            return first.date.formatted(.dateTime.month(.abbreviated))
        }
        return nil
    }

    private func dayDescription(_ day: ActivityDay) -> String {
        "\(day.date.formatted(date: .complete, time: .omitted)): \(day.sessions) \(day.sessions == 1 ? "session" : "sessions"), \(SessionDuration.summary(day.duration)) focused"
    }
}
