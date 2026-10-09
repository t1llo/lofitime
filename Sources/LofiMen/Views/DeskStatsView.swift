import LofiMenCore
import SwiftUI

/// Full-size native statistics, revealed once the camera has zoomed into the computer.
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
            ScrollView {
                Group {
                    if let selectedDay { dayDetails(selectedDay) }
                    else { overview(activity, chartHeight: max(70, min(150, geometry.size.height - 280))) }
                }.padding(20).frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }.scrollIndicators(.hidden)
        }.foregroundStyle(theme.text).background(theme.background).tint(theme.accent)
            .preferredColorScheme(.dark)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("desk-statistics")
            .onChange(of: model.activity.endDate) { _, _ in selectedDay = nil }
    }

    private func overview(_ activity: FocusActivity, chartHeight: CGFloat) -> some View {
        let period = monthSelected ? activity.month : activity.week
        let prefix = monthSelected ? "month" : "week"
        let offset = monthSelected ? $monthOffset : $weekOffset
        let maximum = max(3_600, period.days.map(\.duration).max() ?? 0)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(theme.activity)
                Text("Focus time").font(.room(size: 17, weight: .semibold))
                Spacer()
                HStack(spacing: 2) {
                    periodTab("Week", month: false)
                    periodTab("Month", month: true)
                }.padding(2).background(theme.elevated, in: RoundedRectangle(cornerRadius: 7))
            }
            HStack {
                Text(monthSelected ? period.startDate.formatted(.dateTime.month(.wide).year()) :
                     weekOffset == 0 ? "This week" : period.startDate.formatted(.dateTime.month(.abbreviated).day()) + " – " + period.endDate.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.room(size: 13, weight: .medium)).lineLimit(1)
                    .accessibilityIdentifier("activity-\(prefix)-heading")
                Spacer(minLength: 4)
                IconButton(symbol: "chevron.left", label: "Previous \(prefix)", size: 26) { offset.wrappedValue -= 1 }
                    .disabled(monthSelected ? !activity.canGoToPreviousMonth : !activity.canGoToPreviousWeek)
                    .accessibilityIdentifier("activity-\(prefix)-previous")
                Button("Now") { offset.wrappedValue = 0 }
                    .font(.room(size: 12)).buttonStyle(.plain).foregroundStyle(theme.accent)
                    .accessibilityIdentifier("activity-\(prefix)-current")
                IconButton(symbol: "chevron.right", label: "Next \(prefix)", size: 26) { offset.wrappedValue = min(0, offset.wrappedValue + 1) }
                    .disabled(offset.wrappedValue == 0).accessibilityIdentifier("activity-\(prefix)-next")
            }
            HStack(alignment: .firstTextBaseline, spacing: 17) {
                Text(focusTime(period.totalDuration)).font(.room(size: 34, weight: .light)).monospacedDigit()
                    .foregroundStyle(theme.accent).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("activity-\(prefix)-total")
                Spacer(minLength: 0)
                metric("\(period.totalSessions)", label: "sessions")
                metric("\(period.activeDays)", label: "active days")
                metric(focusTime(period.dailyAverage), label: "daily average")
            }
            VStack(spacing: 7) {
                HStack(alignment: .bottom, spacing: monthSelected ? 3 : 8) {
                    ForEach(period.days) { day in
                        Button { selectedDay = day } label: {
                            VStack(spacing: 4) {
                                if !monthSelected {
                                    Text(day.isInRange ? focusTime(day.duration) : "–")
                                        .font(.room(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3).fill(theme.elevated.opacity(0.5))
                                    RoundedRectangle(cornerRadius: 3).fill(Calendar.current.isDateInToday(day.date) ? theme.accent : theme.activity)
                                        .frame(height: max(day.duration > 0 ? 3 : 0, chartHeight * day.duration / maximum))
                                }.frame(maxWidth: monthSelected ? .infinity : 32).frame(height: chartHeight)
                                if !monthSelected {
                                    Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.room(size: 11))
                                }
                            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!day.isInRange).opacity(day.isInRange ? 1 : 0.3)
                            .help(dayLabel(day)).accessibilityLabel(dayLabel(day))
                            .accessibilityIdentifier("activity-\(monthSelected ? "month-" : "")day-\(day.date.timeIntervalSince1970)")
                    }
                }
                if monthSelected {
                    HStack {
                        Text("1")
                        Spacer()
                        Text("\(period.days.count / 2)")
                        Spacer()
                        Text("\(period.days.count)")
                    }.font(.room(size: 10)).foregroundStyle(theme.muted).accessibilityHidden(true)
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
            HStack {
                Label("\(focusTime(activity.allTimeDuration)) all time", systemImage: "clock")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("activity-all-time")
                Spacer()
                Text("Click a day to explore")
            }.font(.room(size: 11)).foregroundStyle(theme.muted)
        }
    }

    private func periodTab(_ title: String, month: Bool) -> some View {
        Button { monthSelected = month } label: {
            Text(title).font(.room(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                .background(monthSelected == month ? theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).accessibilityAddTraits(monthSelected == month ? .isSelected : [])
            .accessibilityIdentifier(month ? "desk-stats-month" : "desk-stats-week")
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.room(size: 16, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.room(size: 10)).foregroundStyle(theme.muted)
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
                    .buttonStyle(.plain).foregroundStyle(theme.accent).font(.room(size: 13))
                    .accessibilityIdentifier("activity-close-details")
                Spacer()
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.room(size: 14, weight: .medium)).accessibilityIdentifier("activity-session-heading")
            }
            Text("\(SessionDuration.summary(records.reduce(0) { $0 + $1.duration })) focused · \(records.count) sessions")
                .font(.room(size: 12)).foregroundStyle(theme.muted)
            if records.isEmpty {
                Text("No completed sessions on this day.").font(.room(size: 13)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                VStack(spacing: 10) {
                    ForEach(records) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.intention).font(.room(size: 13)).lineLimit(2)
                                Text(record.finishedAt.formatted(date: .omitted, time: .shortened))
                                    .font(.room(size: 11)).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Text(SessionDuration.summary(record.duration)).font(.room(size: 12)).monospacedDigit()
                        }.padding(12).background(theme.surface, in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("session-record-\(record.id)")
                    }
                }
            }
        }
    }
}
