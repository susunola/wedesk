import AppKit
import SwiftUI

/// 全年总览：日历卡点年份后弹出的独立桌面窗口，12 个月一屏看全。
struct YearOverviewView: View {
    let onPickMonth: (Date) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var store: TodoStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var year: Int

    static let cardSize = CGSize(width: 700, height: 500)

    private let columns = 4
    private let monthGap: CGFloat = 12
    private let outerPadding: CGFloat = 18

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    init(
        year: Int,
        onPickMonth: @escaping (Date) -> Void,
        onClose: @escaping () -> Void
    ) {
        _year = State(initialValue: year)
        self.onPickMonth = onPickMonth
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)

            monthGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(outerPadding)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height, alignment: .topLeading)
        .background(CardBackground(material: store.cardMaterial, clarity: store.glassClarity))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    Color.cardBorder(material: store.cardMaterial, colorScheme: colorScheme),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .light ? 0.16 : 0.32),
            radius: 15,
            y: 6
        )
        .padding(WidgetKind.shadowPadding)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Text(String(year))
                .font(.app(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text("全年 \(ChineseCalendarInfo.lunarYearLabel(for: referenceDate))")
                .font(.app(size: 9))
                .foregroundStyle(.tertiary)

            Text("点月份回到日历")
                .font(.app(size: 8.5))
                .foregroundStyle(Color.primary.opacity(0.22))

            Spacer(minLength: 8)

            Button {
                jumpToToday()
            } label: {
                Text("回到今年")
                    .font(.app(size: 9.5, weight: .medium))
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(store.accent.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help("跳回今年的这一月")

            navButton("chevron.left.2", help: "上一年") { shiftYear(-1) }
            navButton("chevron.right.2", help: "下一年") { shiftYear(1) }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.app(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭（Esc）")
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .background(WindowDragRegion())
        .help("拖动标题栏可移动")
    }

    // MARK: - 月份网格

    private var monthGrid: some View {
        let months = monthStarts

        return VStack(spacing: monthGap) {
            ForEach(0..<rowCount, id: \.self) { rowIndex in
                HStack(spacing: monthGap) {
                    ForEach(0..<columns, id: \.self) { columnIndex in
                        let index = rowIndex * columns + columnIndex
                        if index < months.count {
                            miniMonth(months[index])
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var rowCount: Int { (monthStarts.count + columns - 1) / columns }

    /// 这一年的 12 个月首日。
    private var monthStarts: [Date] {
        let calendar = Calendar.current
        guard let january = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return []
        }
        return (0..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: january)
        }
    }

    private func miniMonth(_ monthStart: Date) -> some View {
        let calendar = Calendar.current
        let monthNumber = calendar.component(.month, from: monthStart)

        return Button {
            onPickMonth(monthStart)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(monthNumber)月")
                        .font(.app(size: 10.5, weight: .semibold))
                        .foregroundStyle(
                            calendar.isDate(monthStart, equalTo: store.dayAnchor, toGranularity: .month)
                                ? store.accent
                                : Color.primary.opacity(0.78)
                        )
                    if monthHasMarkers(monthStart) {
                        Circle()
                            .fill(store.accent.opacity(0.75))
                            .frame(width: 3.5, height: 3.5)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    ForEach(weekdaySymbols.indices, id: \.self) { index in
                        Text(weekdaySymbols[index])
                            .font(.app(size: 7, weight: .medium))
                            .foregroundStyle(
                                index >= 5 ? store.accent.opacity(0.45) : Color.primary.opacity(0.26)
                            )
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(spacing: 1) {
                    ForEach(weekRows(monthStart).indices, id: \.self) { rowIndex in
                        HStack(spacing: 0) {
                            ForEach(Array(weekRows(monthStart)[rowIndex].enumerated()), id: \.offset) { _, day in
                                miniDay(day, monthStart: monthStart)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        calendar.isDate(monthStart, equalTo: store.dayAnchor, toGranularity: .month)
                            ? store.accent.opacity(0.07)
                            : Color.primary.opacity(0.025)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func miniDay(_ date: Date?, monthStart: Date) -> some View {
        let calendar = Calendar.current
        let isToday = date.map { calendar.isDate($0, inSameDayAs: store.dayAnchor) } ?? false
        let badge = date.map { ChineseCalendarInfo.badge(for: $0).kind }
        let isHighlighted = badge == .festival || badge == .rest

        return Text(date.map { String(calendar.component(.day, from: $0)) } ?? "")
            .font(.app(size: 8, weight: isToday ? .semibold : .regular))
            .foregroundStyle(
                isToday
                    ? .white
                    : isHighlighted
                        ? Color(nsColor: .systemRed).opacity(0.85)
                        : Color.primary.opacity(0.72)
            )
            .frame(width: 13, height: 13)
            .background {
                if isToday {
                    Circle()
                        .fill(store.accent)
                }
            }
            .frame(maxWidth: .infinity)
    }

    /// 每月固定 6 行，跨月对齐；月首前面的空格留空，不补上月的日子。
    private func weekRows(_ monthStart: Date) -> [[Date?]] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: monthStart),
              let range = calendar.range(of: .day, in: .month, for: interval.start) else {
            return []
        }

        let first = interval.start
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            days.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        while days.count % 7 != 0 { days.append(nil) }
        while days.count > 42 { days.removeLast() }

        var rows: [[Date?]] = []
        var index = 0
        while index < days.count {
            rows.append(Array(days[index..<Swift.min(index + 7, days.count)]))
            index += 7
        }
        while rows.count < 6 { rows.append(Array(repeating: nil, count: 7)) }
        return rows
    }

    private func monthHasMarkers(_ monthStart: Date) -> Bool {
        let calendar = Calendar.current
        let days = store.upcomingCountdownDays.union(store.pendingTodoDays)
        return days.contains { calendar.isDate($0, equalTo: monthStart, toGranularity: .month) }
    }

    // MARK: - 动作

    private var referenceDate: Date {
        let calendar = Calendar.current
        return calendar.date(from: DateComponents(year: year, month: 6, day: 15)) ?? store.dayAnchor
    }

    private func shiftYear(_ delta: Int) {
        year += delta
    }

    private func jumpToToday() {
        let calendar = Calendar.current
        year = calendar.component(.year, from: store.dayAnchor)
        onPickMonth(calendar.startOfDay(for: store.dayAnchor))
    }

    private func navButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
