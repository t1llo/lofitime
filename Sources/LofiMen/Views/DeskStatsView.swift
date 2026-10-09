import LofiMenCore
import SwiftUI

/// A real, accessible desktop UI, mounted over the projected screen of the 3D computer.
struct DeskStatsView: View {
    @Environment(\.roomTheme) private var theme
    @State private var monthSelected = false
    @State private var weekOffset = 0
    @State private var monthOffset = 0
    @State private var selectedDay: ActivityDay?
    var model: AppModel

    private var activity: FocusActivity {
        if weekOffset == 0 && monthOffset == 0 { return model.activity }
        return FocusActivity(records: model.records, through: model.activity.updatedAt,
                             weekOffset: weekOffset, monthOffset: monthOffset)
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 440, geometry.size.height / 255)
            Group {
                if let selectedDay { dayDetails(selectedDay) }
                else { overview(activity) }
            }.padding(16).frame(width: 440, height: 255)
                .scaleEffect(scale).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.foregroundStyle(theme.text).background(theme.background).tint(theme.accent)
            .preferredColorScheme(.dark)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("desk-statistics")
            .onChange(of: model.activity.endDate) { _, _ in selectedDay = nil }
    }

    private func overview(_ activity: FocusActivity) -> some View {
        let period = monthSelected ? activity.month : activity.week
        let prefix = monthSelected ? "month" : "week"
        let offset = monthSelected ? $monthOffset : $weekOffset
        let maximum = max(3_600, period.days.map(\.duration).max() ?? 0)
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(theme.activity)
                Text("Focus time").font(.room(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 2) {
                    periodTab("Week", month: false)
                    periodTab("Month", month: true)
                }.padding(2).background(theme.elevated, in: RoundedRectangle(cornerRadius: 7))
            }
            HStack {
                Text(monthSelected ? period.startDate.formatted(.dateTime.month(.wide).year()) :
                     weekOffset == 0 ? "This week" : period.startDate.formatted(.dateTime.month(.abbreviated).day()) + " – " + period.endDate.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.room(size: 11, weight: .medium)).lineLimit(1)
                    .accessibilityIdentifier("activity-\(prefix)-heading")
                Spacer(minLength: 4)
                IconButton(symbol: "chevron.left", label: "Previous \(prefix)", size: 20) { offset.wrappedValue -= 1 }
                    .disabled(monthSelected ? !activity.canGoToPreviousMonth : !activity.canGoToPreviousWeek)
                    .accessibilityIdentifier("activity-\(prefix)-previous")
                Button("Now") { offset.wrappedValue = 0 }
                    .font(.room(size: 10)).buttonStyle(.plain).foregroundStyle(theme.accent)
                    .accessibilityIdentifier("activity-\(prefix)-current")
                IconButton(symbol: "chevron.right", label: "Next \(prefix)", size: 20) { offset.wrappedValue = min(0, offset.wrappedValue + 1) }
                    .disabled(offset.wrappedValue == 0).accessibilityIdentifier("activity-\(prefix)-next")
            }
            HStack(alignment: .firstTextBaseline, spacing: 17) {
                Text(focusTime(period.totalDuration)).font(.room(size: 29, weight: .light)).monospacedDigit()
                    .foregroundStyle(theme.accent).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("activity-\(prefix)-total")
                Spacer(minLength: 0)
                metric("\(period.totalSessions)", label: "sessions")
                metric("\(period.activeDays)", label: "active days")
                metric(focusTime(period.dailyAverage), label: "daily average")
            }
            HStack(alignment: .bottom, spacing: monthSelected ? 3 : 8) {
                ForEach(period.days) { day in
                    Button { selectedDay = day } label: {
                        VStack(spacing: 4) {
                            if !monthSelected {
                                Text(day.isInRange ? focusTime(day.duration) : "–")
                                    .font(.room(size: 9)).lineLimit(1).minimumScaleFactor(0.65)
                            }
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3).fill(theme.elevated.opacity(0.5))
                                RoundedRectangle(cornerRadius: 3).fill(Calendar.current.isDateInToday(day.date) ? theme.accent : theme.activity)
                                    .frame(height: max(day.duration > 0 ? 3 : 0, 43 * day.duration / maximum))
                            }.frame(maxWidth: monthSelected ? .infinity : 22).frame(height: 43)
                            if !monthSelected {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.room(size: 9))
                            }
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!day.isInRange).opacity(day.isInRange ? 1 : 0.3)
                        .help(dayLabel(day)).accessibilityLabel(dayLabel(day))
                        .accessibilityIdentifier("activity-\(monthSelected ? "month-" : "")day-\(day.date.timeIntervalSince1970)")
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
            HStack {
                Label("\(focusTime(activity.allTimeDuration)) all time", systemImage: "clock")
                Spacer()
                Text("Click a day to explore")
            }.font(.room(size: 9)).foregroundStyle(theme.muted)
        }
    }

    private func periodTab(_ title: String, month: Bool) -> some View {
        Button { monthSelected = month } label: {
            Text(title).font(.room(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(monthSelected == month ? theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityAddTraits(monthSelected == month ? .isSelected : [])
            .accessibilityIdentifier(month ? "desk-stats-month" : "desk-stats-week")
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.room(size: 13, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.room(size: 8)).foregroundStyle(theme.muted)
        }.accessibilityElement(children: .combine)
    }

    private func dayLabel(_ day: ActivityDay) -> String {
        "\(day.date.formatted(date: .complete, time: .omitted)), \(SessionDuration.summary(day.duration)) focused, \(day.sessions) sessions"
    }

    private func dayDetails(_ day: ActivityDay) -> some View {
        let records = model.records.filter {
            Calendar.current.isDate($0.finishedAt, inSameDayAs: day.date) && $0.finishedAt <= model.activity.updatedAt
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { selectedDay = nil } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(theme.accent).font(.room(size: 11))
                    .accessibilityIdentifier("activity-close-details")
                Spacer()
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.room(size: 12, weight: .medium)).accessibilityIdentifier("activity-session-heading")
            }
            Text("\(SessionDuration.summary(day.duration)) focused · \(day.sessions) sessions")
                .font(.room(size: 11)).foregroundStyle(theme.muted)
            if records.isEmpty {
                Text("No completed sessions on this day.").font(.room(size: 12)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(records) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.intention).font(.room(size: 11)).lineLimit(2)
                                    Text(record.finishedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.room(size: 9)).foregroundStyle(theme.muted)
                                }
                                Spacer()
                                Text(SessionDuration.summary(record.duration)).font(.room(size: 11)).monospacedDigit()
                            }.padding(9).background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                                .accessibilityElement(children: .combine).accessibilityIdentifier("session-record-\(record.id)")
                        }
                    }
                }
            }
        }
    }
}
