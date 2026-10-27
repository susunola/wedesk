import AppKit
import Combine
import SwiftUI

/// 今日概览卡：日期、农历/节日、天气、今日与逾期待办、最近倒数日、今日专注统计。
struct TodayWidgetRoot: View {
    @EnvironmentObject private var store: TodoStore
    let onHide: () -> Void

    var body: some View {
        StandaloneWidgetCard(kind: .today, onHide: onHide) {
            TodayPanel(accent: store.accent)
        }
    }
}

struct TodayPanel: View {
    @EnvironmentObject private var store: TodoStore
    @ObservedObject private var weather = WeatherStore.shared
    let accent: Color

    /// 每 30 秒推进一次，跨零点与分钟统计都会自动跟上。
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var agenda: [Todo] { store.todayAgenda }

    private var overdueCount: Int {
        agenda.filter { $0.dueAt.map { $0 < now } ?? false }.count
    }

    private var badge: ChineseCalendarInfo.Badge {
        ChineseCalendarInfo.badge(for: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            rule

            agendaSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            rule

            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 13)
        .onReceive(clock) { date in
            now = date
        }
        .onAppear {
            weather.refreshIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DateUtil.todayLine(for: now))
                    .font(.app(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 5) {
                    Text(ChineseCalendarInfo.fullLunarLabel(for: now))
                        .font(.app(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if badge.kind != .lunar {
                        Text(badge.text)
                            .font(.app(size: 9.5, weight: .medium))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(badgeColor.opacity(0.12))
                            )
                    }

                    weatherChip
                }
            }

            Spacer(minLength: 0)
        }
        // 日期与农历这一带没有任何按钮，可以直接按住拖动卡片。
        .background(WindowDragRegion())
    }

    @ViewBuilder
    private var weatherChip: some View {
        if let symbol = weather.summarySymbol, let summary = weather.summaryText {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.app(size: 9, weight: .medium))
                    .foregroundStyle(accent.opacity(0.85))

                Text(summary)
                    .font(.app(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }

    private var badgeColor: Color {
        switch badge.kind {
        case .lunar:
            return .secondary
        case .festival, .rest:
            return Color(nsColor: .systemRed)
        case .makeup:
            return Color(nsColor: .systemOrange)
        }
    }

    // MARK: - Agenda

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("今日待办")
                    .font(.app(size: 12, weight: .semibold))

                if !agenda.isEmpty {
                    Text("\(agenda.count)")
                        .font(.app(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }

                Spacer(minLength: 4)

                if overdueCount > 0 {
                    Text("逾期 \(overdueCount)")
                        .font(.app(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(TodoStyle.overdue)
                }
            }

            if agenda.isEmpty {
                emptyAgenda
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(agenda) { item in
                            agendaRow(item)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var emptyAgenda: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.app(size: 11, weight: .regular))
                    .foregroundStyle(accent.opacity(0.7))

                Text("今天没有到期的安排")
                    .font(.app(size: 10.5))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }

            if completedToday > 0 {
                Text("今天已完成 \(completedToday) 项")
                    .font(.app(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .padding(.leading, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completedToday: Int {
        let calendar = Calendar.current
        return store.items.filter { item in
            item.done && (item.dueAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }.count
    }

    private func agendaRow(_ item: Todo) -> some View {
        let isOverdue = item.dueAt.map { $0 < now } ?? false

        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    store.toggle(item)
                }
            } label: {
                Image(systemName: "circle")
                    .font(.app(size: 11, weight: .regular))
                    .foregroundStyle(isOverdue ? TodoStyle.overdue : accent.opacity(0.65))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("标记完成")

            Text(item.title)
                .font(.app(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text(dueLabel(for: item, overdue: isOverdue))
                .font(.app(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(isOverdue ? TodoStyle.overdue : Color.secondary.opacity(0.8))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 3.5)
        .padding(.horizontal, 2)
    }

    private func dueLabel(for item: Todo, overdue: Bool) -> String {
        guard let due = item.dueAt else { return "" }
        if overdue, !Calendar.current.isDateInToday(due) {
            return "\(DateUtil.monthDay(due)) \(DateUtil.timeOnly(due))"
        }
        return DateUtil.todoDueLabel(due, now: now)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let countdown = store.nextCountdown {
                let delta = DateUtil.dayDelta(to: countdown.date, from: now)
                footerRow(
                    symbol: "hourglass",
                    color: accent,
                    leading: "距 \(countdown.title)",
                    trailing: delta == 0 ? "就是今天" : "还有 \(delta) 天"
                )
            } else {
                footerRow(
                    symbol: "hourglass",
                    color: Color.secondary.opacity(0.6),
                    leading: "暂无倒数日",
                    trailing: ""
                )
            }

            footerRow(
                symbol: "timer",
                color: store.pomodoro.stats.sessions > 0 ? accent : Color.secondary.opacity(0.6),
                leading: "今日专注",
                trailing: "\(store.pomodoro.stats.sessions) 段 · \(store.pomodoro.stats.minutes) 分钟"
            )
        }
    }

    private func footerRow(symbol: String, color: Color, leading: String, trailing: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.app(size: 9.5, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 12)

            Text(leading)
                .font(.app(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(trailing)
                .font(.app(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(trailing.isEmpty ? Color.clear : color)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }
}
