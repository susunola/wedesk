import AppKit
import SwiftUI

enum DateUtil {
    private static let locale = Locale(identifier: "zh_CN")

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    private static let dayWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy年M月d日 EEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static func dayDelta(to date: Date, from base: Date = Date()) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: base),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }

    static func todayLine(for date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return (isThisYear ? dayFormatter : dayWithYearFormatter).string(from: date)
    }

    static func monthDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return (isThisYear ? monthDayFormatter : monthDayYearFormatter).string(from: date)
    }

    static func timeOnly(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func weekdayName(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    /// 温度统一取整并带上度数符号。
    static func temperature(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func todoDueLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        // 落在午夜的到期时间代表"全天"，不带时刻。
        let time = calendar.startOfDay(for: date) == date ? "" : " " + timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "今天\(time)"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天\(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天\(time)"
        }

        let delta = dayDelta(to: date, from: now)
        if delta > 1 && delta < 7 {
            return "\(weekdayFormatter.string(from: date))\(time)"
        }

        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = (isThisYear ? monthDayFormatter : monthDayYearFormatter).string(from: date)
        return "\(day)\(time)"
    }

    static func todoAbsoluteLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        let day = (isThisYear ? monthDayFormatter : monthDayYearFormatter).string(from: date)
        return "\(day) \(weekdayFormatter.string(from: date)) \(timeFormatter.string(from: date))"
    }

    static func defaultTodoDueDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        if let six = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now),
           six > now.addingTimeInterval(1800) {
            return six
        }
        return todoTomorrowMorning()
    }

    static func todoOneHourLater() -> Date {
        let raw = Date().addingTimeInterval(3600)
        let rounded = (raw.timeIntervalSince1970 / 300).rounded() * 300
        return Date(timeIntervalSince1970: rounded)
    }

    static func todoTomorrowMorning() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Calendar

/// 网格中的一个格子；相邻月份补位的日子会淡化显示，让月份连成一片。
private struct CalendarSlot {
    let date: Date
    let isAdjacent: Bool
}

struct CalendarPopover: View {
    let accent: Color
    var countdownDays: Set<Date> = []
    var todoDays: Set<Date> = []
    var tasksProvider: ((Date) -> [Todo])? = nil
    var onToggleTask: ((Todo) -> Void)? = nil
    var onAddTask: ((String, Date) -> Void)? = nil
    var selection: Binding<Date>? = nil
    var initialMonth: Date? = nil
    var onPick: (() -> Void)? = nil
    /// 由外部传入的"今天"，跨午夜时刷新，保证高亮不会停在旧日子。
    var dayAnchor = Date()

    @State private var month = Date()
    @State private var presentedDay: Date?
    @State private var lastAnchor = Date()

    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    /// 选日期的弹出层只显示本月，避免点了灰色日子后日历没翻页。
    private var showsAdjacentDays: Bool { selection == nil }

    var body: some View {
        let lunarMonth = ChineseCalendarInfo.lunarMonthName(for: month)

        VStack(spacing: 0) {
            headerBar(lunarMonth: lunarMonth)
                .padding(.bottom, 6)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.app(size: 9.5, weight: .medium))
                        .foregroundStyle(index >= 5 ? accent.opacity(0.62) : Color.primary.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.055))
                    .frame(height: 0.5)
            }

            // 行高等分整张卡片，字号才敢放大；弹出层没有确定高度时自然退回内容高度。
            VStack(spacing: 0) {
                ForEach(rowsOfCells.indices, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        ForEach(Array(rowsOfCells[rowIndex].enumerated()), id: \.offset) { _, slot in
                            dayCell(slot)
                        }
                    }
                    .frame(maxHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 3)

            if let scheduleNote {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.app(size: 8))
                    Text(scheduleNote)
                        .font(.app(size: 8.5))
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
            } else if selection == nil {
                legend
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .onAppear {
            month = initialMonth ?? selection?.wrappedValue ?? dayAnchor
            lastAnchor = dayAnchor
        }
        .onChange(of: dayAnchor) { _, newValue in
            let calendar = Calendar.current
            // 只在当前显示的仍是"自动跟着今天"那个月时翻页；用户自己翻到别的月份看日子时不打断。
            if calendar.isDate(month, equalTo: lastAnchor, toGranularity: .month) {
                month = newValue
            }
            lastAnchor = newValue
        }
    }

    /// 按周切行，方便每行等分卡片剩余高度。
    private var rowsOfCells: [[CalendarSlot?]] {
        let items = cells
        var rows: [[CalendarSlot?]] = []
        var index = 0
        while index < items.count {
            let end = Swift.min(index + 7, items.count)
            rows.append(Array(items[index..<end]))
            index = end
        }
        return rows
    }

    private func headerBar(lunarMonth: String) -> some View {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: month)
        let monthNumber = calendar.component(.month, from: month)

        return HStack(spacing: 0) {
            Button {
                month = dayAnchor
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(monthNumber)月")
                        .font(.app(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(String(year))
                        .font(.app(size: 10, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.32))

                    if !lunarMonth.isEmpty {
                        Text("农历\(lunarMonth)")
                            .font(.app(size: 8.5))
                            .foregroundStyle(Color.primary.opacity(0.26))
                    }

                    if isProvisionalYear {
                        Text("预测")
                            .font(.app(size: 7, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color(nsColor: .systemOrange).opacity(0.12)))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("回到今天")

            Spacer(minLength: 6)

            HStack(spacing: 0) {
                navButton("chevron.left.2", help: "上一年", size: 8, width: 17) { shiftYear(-1) }
                navButton("chevron.left", help: "上个月", size: 9.5, width: 17) { shiftMonth(-1) }
                navButton("chevron.right", help: "下个月", size: 9.5, width: 17) { shiftMonth(1) }
                navButton("chevron.right.2", help: "下一年", size: 8, width: 17) { shiftYear(1) }
            }
        }
        .frame(height: 20)
    }

    /// 图例：解释日子下面那几个小标记，顺便填住卡片底部的空白。
    private var legend: some View {
        HStack(spacing: 9) {
            HStack(spacing: 3) {
                Circle()
                    .fill(accent)
                    .frame(width: 3, height: 3)
                Text("倒数日")
            }

            HStack(spacing: 3) {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.40), lineWidth: 1)
                    .frame(width: 4, height: 4)
                Text("待办")
            }

            HStack(spacing: 3) {
                legendChip("休", Color(nsColor: .systemRed))
                Text("放假")
            }

            HStack(spacing: 3) {
                legendChip("班", Color(nsColor: .systemOrange))
                Text("补班")
            }
        }
        .font(.app(size: 7.5))
        .foregroundStyle(Color.primary.opacity(0.32))
    }

    private func legendChip(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.app(size: 6.5, weight: .semibold))
            .foregroundStyle(tint.opacity(0.88))
            .frame(width: 11, height: 10)
            .background(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func navButton(
        _ systemName: String,
        help: String,
        size: CGFloat,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.app(size: size, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: width, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func dayCell(_ slot: CalendarSlot?) -> some View {
        Group {
            if let slot {
                let date = slot.date
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: date)
                let isAdjacent = slot.isAdjacent
                let isToday = calendar.isDate(date, inSameDayAs: dayAnchor)
                let isSelected = selection.map { calendar.isDate(date, inSameDayAs: $0.wrappedValue) } ?? false
                let isFilled = !isAdjacent && (selection == nil ? isToday : isSelected)
                let badge = ChineseCalendarInfo.badge(for: date)
                let hasCountdown = !isAdjacent && countdownDays.contains(start)
                let hasTodo = !isAdjacent && todoDays.contains(start)

                let cell = VStack(spacing: 1) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.app(
                            size: isAdjacent ? 10.5 : 12,
                            weight: isToday || isSelected ? .semibold : .medium
                        ))
                        .foregroundStyle(dayNumberColor(
                            isAdjacent: isAdjacent,
                            isToday: isToday,
                            isSelected: isSelected,
                            isFilled: isFilled
                        ))
                        .frame(width: 23, height: 23)
                        .background {
                            if isFilled {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [accent, accent.opacity(0.80)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: accent.opacity(0.32), radius: 3, y: 1.5)
                            } else if isSelected {
                                Circle()
                                    .fill(accent.opacity(0.13))
                                    .overlay(Circle().strokeBorder(accent.opacity(0.42), lineWidth: 0.8))
                            } else if isToday && !isAdjacent {
                                Circle()
                                    .strokeBorder(accent.opacity(0.50), lineWidth: 1)
                            }
                        }

                    badgeRow(
                        badge: badge,
                        date: date,
                        isAdjacent: isAdjacent,
                        isToday: isToday,
                        hasCountdown: hasCountdown,
                        hasTodo: hasTodo
                    )
                    .frame(height: 10)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())

                if isAdjacent {
                    // 补位的日子用来翻页，不弹当天的待办。
                    cell
                        .onTapGesture { month = start }
                        .help("跳到这个月")
                } else if let selection {
                    Button {
                        selection.wrappedValue = start
                        onPick?()
                    } label: {
                        cell
                    }
                    .buttonStyle(.plain)
                } else {
                    cell
                        .onTapGesture {
                            presentedDay = start
                        }
                        .popover(isPresented: dayPopoverBinding(for: date), arrowEdge: .bottom) {
                            DayTasksPopover(
                                date: date,
                                accent: accent,
                                tasks: tasksProvider?(date) ?? [],
                                onToggle: { onToggleTask?($0) },
                                onAdd: onAddTask
                            )
                            .frame(width: 262)
                        }
                }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func dayNumberColor(
        isAdjacent: Bool,
        isToday: Bool,
        isSelected: Bool,
        isFilled: Bool
    ) -> Color {
        if isFilled { return .white }
        if isAdjacent { return Color.primary.opacity(0.26) }
        if isToday || isSelected { return accent }
        return Color.primary.opacity(0.85)
    }

    @ViewBuilder
    private func badgeRow(
        badge: ChineseCalendarInfo.Badge,
        date: Date,
        isAdjacent: Bool,
        isToday: Bool,
        hasCountdown: Bool,
        hasTodo: Bool
    ) -> some View {
        HStack(spacing: 2) {
            if isAdjacent {
                // 相邻月份只留日子数字，下面保持空白。
            } else {
                badgeLabel(badge: badge, date: date, isToday: isToday)

                if hasCountdown {
                    Circle()
                        .fill(accent)
                        .frame(width: 3, height: 3)
                }

                if hasTodo {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.40), lineWidth: 1)
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    @ViewBuilder
    private func badgeLabel(
        badge: ChineseCalendarInfo.Badge,
        date: Date,
        isToday: Bool
    ) -> some View {
        switch badge.kind {
        case .rest, .makeup:
            // 休/班做成小色块，比一片红橙字安静。
            let tint = badge.kind == .rest ? Color(nsColor: .systemRed) : Color(nsColor: .systemOrange)
            Text(badge.text)
                .font(.app(size: 7.5, weight: .semibold))
                .foregroundStyle(tint.opacity(0.90))
                .frame(width: 12, height: 11)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint.opacity(0.13))
                )
        case .festival:
            Text(badge.text)
                .font(.app(size: 8.5, weight: .medium))
                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.80))
        case .lunar:
            // 农历比阳历小一档、颜色更淡，但必须一眼读得清。
            let isMonthStart = ChineseCalendarInfo.isLunarMonthStart(date)
            Text(badge.text)
                .font(.app(size: 8.5, weight: isMonthStart ? .semibold : .regular))
                .foregroundStyle(
                    isToday
                        ? accent.opacity(0.90)
                        : Color.primary.opacity(isMonthStart ? 0.62 : 0.48)
                )
        }
    }

    private func dayPopoverBinding(for date: Date) -> Binding<Bool> {
        Binding(
            get: {
                guard let presentedDay else { return false }
                return Calendar.current.isDate(presentedDay, inSameDayAs: date)
            },
            set: { presented in
                if !presented { self.presentedDay = nil }
            }
        )
    }

    private var scheduleNote: String? {
        if displayYear == 2027 {
            return "2027 年放假安排为预测版，待国务院公布"
        }
        if displayYear >= 2028 {
            return "\(displayYear) 年放假安排待公布"
        }
        return nil
    }

    private var displayYear: Int {
        Calendar.current.component(.year, from: month)
    }

    private var isProvisionalYear: Bool {
        displayYear == 2027
    }

    private var cells: [CalendarSlot?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }

        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30

        func slot(_ date: Date?, adjacent: Bool) -> CalendarSlot? {
            guard let date else { return nil }
            // 选日期的弹出层不补相邻月份的日子，本月照常。
            if adjacent && !showsAdjacentDays { return nil }
            return CalendarSlot(date: date, isAdjacent: adjacent)
        }

        var result: [CalendarSlot?] = (0..<leading).map { index in
            slot(calendar.date(byAdding: .day, value: index - leading, to: first), adjacent: true)
        }
        for offset in 0..<dayCount {
            result.append(
                slot(calendar.date(byAdding: .day, value: offset, to: first), adjacent: false)
            )
        }
        var trailing = 0
        while result.count % 7 != 0 {
            result.append(
                slot(calendar.date(byAdding: .day, value: dayCount + trailing, to: first), adjacent: true)
            )
            trailing += 1
        }
        return result
    }

    private func shiftMonth(_ delta: Int) {
        let calendar = Calendar.current
        let base = calendar.dateInterval(of: .month, for: month)?.start ?? month
        if let next = calendar.date(byAdding: .month, value: delta, to: base) {
            month = next
        }
    }

    private func shiftYear(_ delta: Int) {
        let calendar = Calendar.current
        let base = calendar.dateInterval(of: .month, for: month)?.start ?? month
        if let next = calendar.date(byAdding: .year, value: delta, to: base) {
            month = next
        }
    }
}

// MARK: - Day tasks (calendar ↔ todo)

struct DayTasksPopover: View {
    let date: Date
    let accent: Color
    let tasks: [Todo]
    let onToggle: (Todo) -> Void
    var onAdd: ((String, Date) -> Void)? = nil

    @ObservedObject private var systemStore = SystemCalendarStore.shared
    @State private var draft = ""

    private let visibleEventLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)

            eventsSection

            sectionLabel("待办", count: tasks.count)

            tasksSection

            if onAdd != nil {
                composer
            }
        }
        .padding(10)
        .onAppear { systemStore.load(date) }
        .onChange(of: date) { _, newValue in
            systemStore.load(newValue)
            draft = ""
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(DateUtil.shortDate(date))
                .font(.app(size: 11.5, weight: .semibold))
            Text(ChineseCalendarInfo.fullLunarLabel(for: date))
                .font(.app(size: 8.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: 苹果日历

    @ViewBuilder
    private var eventsSection: some View {
        let events = systemStore.events
        if !events.isEmpty {
            sectionLabel("苹果日历", count: events.count)

            ForEach(events.prefix(visibleEventLimit)) { event in
                SystemEventRow(event: event)
            }

            if events.count > visibleEventLimit {
                Text("还有 \(events.count - visibleEventLimit) 条日程")
                    .font(.app(size: 8.5))
                    .foregroundStyle(.tertiary)
            }
        } else if systemStore.access != .granted {
            accessRow
        }
    }

    private var accessRow: some View {
        let isBlocked = systemStore.access == .blocked || systemStore.access == .writeOnly

        return HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.app(size: 9))
            Text(systemStore.access.hintText)
                .font(.app(size: 9))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(systemStore.isBusy ? "申请中" : (isBlocked ? "去开启" : "允许读取")) {
                if isBlocked {
                    systemStore.openPrivacySettings()
                } else {
                    systemStore.requestAccess()
                }
            }
            .buttonStyle(.borderless)
            .font(.app(size: 9, weight: .medium))
            .foregroundStyle(accent)
        }
        .foregroundStyle(.tertiary)
        .padding(.vertical, 1)
    }

    // MARK: 待办

    @ViewBuilder
    private var tasksSection: some View {
        if tasks.isEmpty {
            Text("这一天还没有待办")
                .font(.app(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } else {
            ForEach(tasks) { task in
                DayTaskRow(task: task, accent: accent, onToggle: onToggle)
            }
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.app(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("\(count)")
                .font(.app(size: 8.5).monospacedDigit())
                .foregroundStyle(.tertiary.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }

    // MARK: 快速记录

    private var composer: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.app(size: 9))
                .foregroundStyle(.tertiary)

            TextField("记一件事，回车保存", text: $draft)
                .font(.app(size: 10.5))
                .textFieldStyle(.plain)
                .onSubmit(submit)

            if hasDraft {
                Button("添加") { submit() }
                    .buttonStyle(.borderless)
                    .font(.app(size: 9.5, weight: .medium))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(accent.opacity(hasDraft ? 0.34 : 0.16), lineWidth: 0.6)
        )
        .padding(.top, 2)
    }

    private var hasDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let onAdd else { return }
        onAdd(text, date)
        draft = ""
    }
}

/// 苹果日历里的一条日程，只读展示。
struct SystemEventRow: View {
    let event: SystemEvent

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(event.tint.opacity(0.85))
                .frame(width: 2.5, height: 13)

            Text(event.timeText)
                .font(.app(size: 9.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 33, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.app(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(event.calendarTitle)
                    .font(.app(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

struct DayTaskRow: View {
    let task: Todo
    let accent: Color
    let onToggle: (Todo) -> Void

    @State private var hovered = false

    private var isOverdue: Bool {
        task.isOverdue()
    }

    var body: some View {
        HStack(spacing: 7) {
            Button {
                onToggle(task)
            } label: {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1.2)
                    .frame(width: 12, height: 12)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("标记完成")

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.app(size: 11, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    if let due = task.dueAt {
                        Text(task.isAllDay ? "全天" : DateUtil.timeOnly(due))
                            .font(.app(size: 9.5).monospacedDigit())
                            .foregroundStyle(isOverdue ? Color(nsColor: .systemRed) : Color.secondary)
                    }
                    ForEach(task.people, id: \.self) { person in
                        Text("@\(person)")
                            .font(.app(size: 9))
                            .foregroundStyle(accent)
                    }
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - Countdowns

struct CountdownPopover: View {
    @EnvironmentObject private var store: TodoStore
    let accent: Color
    /// 作为桌面卡片使用时列表吃掉多余高度；在弹出层里仍按内容高度显示。
    var fillHeight = false

    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var hoveredID: UUID?
    @State private var showDatePicker = false
    @State private var showMorePresets = false

    private var events: [Countdown] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let upcoming = store.countdowns
            .filter { calendar.startOfDay(for: $0.date) >= today }
            .sorted { $0.date < $1.date }
        let past = store.countdowns
            .filter { calendar.startOfDay(for: $0.date) < today }
            .sorted { $0.date > $1.date }
        return upcoming + past
    }

    private var listHeight: CGFloat {
        min(CGFloat(events.count) * 37, 185)
    }

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("倒数日")
                    .font(.app(size: 12, weight: .semibold))

                if !store.countdowns.isEmpty {
                    Text("\(store.countdowns.count)")
                        .font(.app(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }

            Group {
                if events.isEmpty {
                    Text("还没有倒数日，添加一个重要日子吧")
                        .font(.app(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(events) { event in
                                CountdownRow(
                                    event: event,
                                    accent: accent,
                                    hovered: hoveredID == event.id
                                )
                                .onHover { inside in
                                    if inside {
                                        hoveredID = event.id
                                    } else if hoveredID == event.id {
                                        hoveredID = nil
                                    }
                                }

                                if event.id != events.last?.id {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 0.5)
                                }
                            }
                        }
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: fillHeight ? .infinity : listHeight,
                alignment: events.isEmpty ? .center : .topLeading
            )

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)

            HStack(spacing: 5) {
                ForEach(CountdownPresets.popular) { preset in
                    CountdownPresetChip(
                        preset: preset,
                        date: CountdownPresets.nextDate(for: preset.rule),
                        added: isPresetAdded(preset),
                        accent: accent
                    ) {
                        add(preset)
                    }
                }

                Button {
                    showMorePresets.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text("更多")
                            .font(.app(size: 10, weight: .medium))
                        Image(systemName: "ellipsis")
                            .font(.app(size: 8.5, weight: .semibold))
                    }
                    .foregroundStyle(showMorePresets ? accent : Color.primary.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(showMorePresets ? 0.09 : 0.05)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showMorePresets, arrowEdge: .top) {
                    CountdownPresetMorePanel(accent: accent) { preset in
                        add(preset)
                    }
                }

                Spacer(minLength: 0)
            }

            TextField("名称，如：述职汇报", text: $title)
                .textFieldStyle(.plain)
                .font(.app(size: 11.5))
                .onSubmit(add)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            HStack(spacing: 8) {
                Button {
                    showDatePicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.app(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(DateUtil.shortDate(date))
                            .font(.app(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("选择日期")
                .popover(isPresented: $showDatePicker, arrowEdge: .top) {
                    CalendarPopover(accent: accent, selection: $date) {
                        showDatePicker = false
                    }
                    .frame(width: 260)
                }

                Spacer(minLength: 0)

                Button(action: add) {
                    Text("添加")
                        .font(.app(size: 10.5, weight: .semibold))
                        .foregroundStyle(canAdd ? Color.white : Color.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(canAdd ? accent : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func add() {
        guard canAdd else { return }
        store.addCountdown(title, on: date)
        title = ""
        if let next = Calendar.current.date(byAdding: .day, value: 7, to: Date()) {
            date = next
        }
        hoveredID = nil
    }

    private func add(_ preset: CountdownPreset) {
        guard !isPresetAdded(preset) else { return }
        store.addCountdown(preset.title, on: CountdownPresets.nextDate(for: preset.rule))
        hoveredID = nil
    }

    private func isPresetAdded(_ preset: CountdownPreset) -> Bool {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: CountdownPresets.nextDate(for: preset.rule))
        return store.countdowns.contains {
            $0.title == preset.title && calendar.startOfDay(for: $0.date) == target
        }
    }
}

struct CountdownPresetChip: View {
    let preset: CountdownPreset
    let date: Date
    let added: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if added {
                    Image(systemName: "checkmark")
                        .font(.app(size: 8, weight: .bold))
                }
                Text(preset.title)
                    .font(.app(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(added ? Color.secondary : (hovered ? accent : Color.primary.opacity(0.72)))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(added ? 0.03 : (hovered ? 0.09 : 0.05))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .onHover { inside in hovered = inside }
        .help("\(preset.title) · \(DateUtil.monthDay(date))")
    }
}

struct CountdownPresetMorePanel: View {
    let accent: Color
    let onPick: (CountdownPreset) -> Void

    @State private var hoveredID: String?

    private var rows: [(preset: CountdownPreset, date: Date)] {
        CountdownPresets.more.map { ($0, CountdownPresets.nextDate(for: $0.rule)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("更多节日")
                .font(.app(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ForEach(rows, id: \.preset.id) { row in
                Button {
                    onPick(row.preset)
                } label: {
                    HStack(spacing: 7) {
                        Text(row.preset.title)
                            .font(.app(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        Text(DateUtil.monthDay(row.date))
                            .font(.app(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(DateUtil.dayDelta(to: row.date)) 天")
                            .font(.app(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(accent)
                            .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(hoveredID == row.preset.id ? 0.06 : 0))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        hoveredID = row.preset.id
                    } else if hoveredID == row.preset.id {
                        hoveredID = nil
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 196)
    }
}

struct CountdownRow: View {
    @EnvironmentObject private var store: TodoStore
    let event: Countdown
    let accent: Color
    let hovered: Bool

    var body: some View {
        let delta = DateUtil.dayDelta(to: event.date)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.app(size: 11.5, weight: .medium))
                    .foregroundStyle(delta < 0 ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(DateUtil.shortDate(event.date))
                    .font(.app(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            Text(delta == 0 ? "今天" : (delta > 0 ? "\(delta) 天" : "已过 \(-delta) 天"))
                .font(.app(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(delta < 0 ? Color.secondary.opacity(0.65) : accent)
                .fixedSize()

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.deleteCountdown(event)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.app(size: 7.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .opacity(delta < 0 ? 0.6 : 1)
        .contextMenu {
            Button("删除", role: .destructive) {
                store.deleteCountdown(event)
            }
        }
    }
}
