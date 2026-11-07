import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.colorScheme) private var colorScheme
    var onHideAll: (() -> Void)? = nil
    var onHideSelf: (() -> Void)? = nil
    var onOpenLibrary: (() -> Void)? = nil
    var onResetPositions: (() -> Void)? = nil

    @State private var draft = ""
    @State private var draftDue: Date?
    @State private var draftReminderLead = 0
    @State private var showDraftSchedule = false
    @State private var showCalendar = false
    @State private var showCountdowns = false
    @State private var todayTick = Date()
    @State private var hovering = false
    @FocusState private var focused: Bool

    private let minuteTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var progress: Double {
        guard !store.items.isEmpty else { return 0 }
        return Double(store.completed) / Double(store.items.count)
    }

    var body: some View {
        GeometryReader { proxy in
            let card = WidgetKind.todo.cardSize(for: proxy.size)

            VStack(spacing: 0) {
                header
                hairline
                dateBar
                listSection
                    .frame(maxHeight: .infinity)
                hairline
                composer
            }
            .frame(width: card.width, height: card.height)
            .background(
                CardBackground(material: store.cardMaterial, clarity: store.glassClarity)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Color.cardBorder(material: store.cardMaterial, colorScheme: colorScheme),
                        lineWidth: 0.5
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                WidgetResizeHandle(kind: .todo, visible: hovering)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.16 : 0.32),
                radius: 15,
                y: 6
            )
            .padding(WidgetKind.shadowPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering = $0 }
        .tint(store.accent)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            todayTick = Date()
        }
        .onReceive(minuteTimer) { date in
            todayTick = date
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }

    // MARK: - Date bar

    private var dateBar: some View {
        HStack(spacing: 8) {
            Button {
                showCountdowns = false
                showCalendar.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.app(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Text(DateUtil.todayLine(for: todayTick))
                        .font(.app(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看日历")
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                CalendarPopover(
                    accent: store.accent,
                    countdownDays: store.upcomingCountdownDays,
                    todoDays: store.pendingTodoDays,
                    tasksProvider: { store.pendingTodos(on: $0) },
                    onToggleTask: { store.toggle($0) },
                    dayAnchor: store.dayAnchor
                )
                    .frame(width: 260)
            }

            Spacer(minLength: 8)

            countdownChip
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private var countdownChip: some View {
        Button {
            showCalendar = false
            showCountdowns.toggle()
        } label: {
            Group {
                if let next = store.nextCountdown {
                    let delta = DateUtil.dayDelta(to: next.date, from: todayTick)
                    let dayText = delta == 0 ? "今天" : "\(delta) 天"
                    let title = next.title.count > 8 ? String(next.title.prefix(8)) + "…" : next.title

                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.app(size: 8.5, weight: .semibold))

                        Text("\(title) · \(dayText)")
                            .lineLimit(1)
                    }
                    .font(.app(size: 10, weight: .medium))
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(store.accent.opacity(0.10)))
                } else if !store.countdowns.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.app(size: 8.5, weight: .semibold))

                        Text("倒数日 · \(store.countdowns.count)")
                            .lineLimit(1)
                    }
                    .font(.app(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.app(size: 7.5, weight: .bold))

                        Text("倒数日")
                            .font(.app(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.primary.opacity(0.045)))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(store.countdowns.isEmpty ? "添加倒数日" : "管理倒数日")
        .popover(isPresented: $showCountdowns, arrowEdge: .bottom) {
            CountdownPopover(accent: store.accent)
                .frame(width: 262)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            if store.showAvatar, let image = store.avatarImage {
                AvatarRing(image: image, progress: progress, accent: store.accent)
            } else {
                ProgressRing(progress: progress, accent: store.accent)
            }

            Text("待办")
                .font(.app(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if !store.items.isEmpty {
                Text("\(store.completed)/\(store.items.count)")
                    .font(.app(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                    .contentTransition(.numericText())
            }

            headerButton(
                systemName: "minus",
                active: false
            ) {
                onHideAll?()
            }
            .help("收起所有小组件 (⌘M / ⌃⌥T)")

            headerButton(
                systemName: store.pinned ? "pin.fill" : "pin.slash",
                active: store.pinned
            ) {
                store.setPinned(!store.pinned)
            }
            .help(store.pinned ? "已钉在桌面：始终停留在所有窗口之后" : "未钉住：像普通窗口一样参与排列")

            Menu {
                Menu("头像") {
                    Toggle("显示头像", isOn: Binding(
                        get: { store.showAvatar },
                        set: { store.setShowAvatar($0) }
                    ))
                    Button("更换图片…") { store.chooseAvatar() }
                    Button("恢复默认图片") { store.resetAvatar() }
                }
                Menu("主题色") {
                    ForEach(Palette.accents) { accent in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                store.setAccent(accent.id)
                            }
                        } label: {
                            Label {
                                Text(accent.name + (store.accentIndex == accent.id ? "  ✓" : ""))
                            } icon: {
                                Image(nsImage: Palette.swatch(for: accent.color))
                            }
                        }
                    }
                }
                Divider()
                Button("小组件库…") {
                    DispatchQueue.main.async { onOpenLibrary?() }
                }
                Button("从桌面移除待办组件") {
                    DispatchQueue.main.async { onHideSelf?() }
                }
                Button("重置所有组件排列") {
                    DispatchQueue.main.async { onResetPositions?() }
                }
                Divider()
                Button("收起所有小组件") {
                    DispatchQueue.main.async { onHideAll?() }
                }
                Button("清除已完成") { store.clearCompleted() }
                    .disabled(store.completed == 0)
                Divider()
                Button("退出待办") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.app(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(WindowDragRegion())
    }

    private func headerButton(systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.app(size: 10.5, weight: .semibold))
                .foregroundStyle(active ? store.accent : Color.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var listSection: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(store.items) { item in
                            TodoRow(item: item, now: todayTick)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 7)
                    .animation(.easeOut(duration: 0.2), value: store.items)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(store.accent.opacity(0.09))
                    .frame(width: 46, height: 46)
                Image(systemName: "checkmark")
                    .font(.app(size: 17, weight: .semibold))
                    .foregroundStyle(store.accent.opacity(0.85))
            }
            .padding(.bottom, 2)

            Text("今天还没有待办")
                .font(.app(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

            Text("用 @ 标记相关人，点时钟设置截止时间")
                .font(.app(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.app(size: 10.5, weight: .bold))
                    .foregroundStyle(focused ? store.accent : Color.secondary)

                TextField("添加待办，@ 相关人…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.app(size: 12.5))
                    .focused($focused)
                    .onSubmit(commit)

                scheduleButton
                mentionMenu
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(focused ? 0.07 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(store.accent.opacity(focused ? 0.45 : 0), lineWidth: 1)
            )

            if let due = draftDue {
                draftScheduleChip(due)
            }
        }
        .padding(11)
        .animation(.easeOut(duration: 0.16), value: focused)
        .animation(.easeOut(duration: 0.16), value: draftDue)
    }

    private var scheduleButton: some View {
        Button {
            if draftDue == nil {
                draftDue = DateUtil.defaultTodoDueDate()
                draftReminderLead = 0
            }
            showDraftSchedule = true
        } label: {
            Image(systemName: draftDue == nil ? "clock" : "clock.fill")
                .font(.app(size: 11, weight: .medium))
                .foregroundStyle(draftDue == nil ? Color.secondary : store.accent)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(draftDue == nil ? Color.clear : store.accent.opacity(0.11))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(draftDue == nil ? "设置截止时间和提醒" : "修改截止时间")
        .popover(isPresented: $showDraftSchedule, arrowEdge: .bottom) {
            SchedulePopover(
                date: Binding(
                    get: { draftDue ?? DateUtil.defaultTodoDueDate() },
                    set: { draftDue = $0 }
                ),
                reminderLead: $draftReminderLead,
                accent: store.accent,
                onClear: {
                    draftDue = nil
                    draftReminderLead = 0
                    showDraftSchedule = false
                    focused = true
                },
                onDone: {
                    showDraftSchedule = false
                    focused = true
                }
            )
        }
    }

    private var mentionMenu: some View {
        Menu {
            let people = store.knownPeople
            if !people.isEmpty {
                ForEach(Array(people.prefix(6)), id: \.self) { person in
                    Button("@\(person)") { insertMention(person) }
                }
                Divider()
            }
            Button("输入 @ 人名") { insertMention("") }
        } label: {
            Image(systemName: "at")
                .font(.app(size: 11, weight: .medium))
                .foregroundStyle(draftMentions.isEmpty ? Color.secondary : store.accent)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(draftMentions.isEmpty ? Color.clear : store.accent.opacity(0.11))
                )
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("标记相关人")
    }

    private var draftMentions: [String] {
        MentionParser.extract(from: draft)
    }

    private func insertMention(_ person: String) {
        if !draft.isEmpty, !draft.hasSuffix(" "), !draft.hasSuffix("\u{3000}") {
            draft += " "
        }
        draft += "@" + person
        if !person.isEmpty {
            draft += " "
        }
        focused = true
    }

    private func draftScheduleChip(_ due: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.app(size: 8.5, weight: .semibold))

            Text(DateUtil.todoDueLabel(due))
                .font(.app(size: 9.5, weight: .semibold))

            Text("·")
                .font(.app(size: 9))
                .opacity(0.45)

            Image(systemName: draftReminderLead >= 0 ? "bell.fill" : "bell.slash")
                .font(.app(size: 7.5, weight: .semibold))

            Text(ReminderChoice.label(for: draftReminderLead))
                .font(.app(size: 9.5, weight: .medium))

            Spacer(minLength: 0)

            Button {
                draftDue = nil
                draftReminderLead = 0
            } label: {
                Image(systemName: "xmark")
                    .font(.app(size: 7, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("清除截止时间")
        }
        .foregroundStyle(store.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(Capsule().fill(store.accent.opacity(0.09)))
        .padding(.top, 7)
        .padding(.horizontal, 1)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let due = draftDue
        let lead = due == nil ? nil : (draftReminderLead >= 0 ? draftReminderLead : nil)

        draft = ""
        draftDue = nil
        draftReminderLead = 0
        showDraftSchedule = false

        _ = withAnimation(.easeOut(duration: 0.2)) {
            store.add(text, dueAt: due, reminderLead: lead)
        }
        focused = true

        if lead != nil, let due, due > Date() {
            ReminderCenter.shared.requestAccessWithAlert()
        }
    }

    // MARK: - Drag handled natively by WindowDragRegion (AppKit window drag)
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.13), lineWidth: 1.8)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 15, height: 15)
        .animation(.easeOut(duration: 0.28), value: progress)
    }
}

// MARK: - Avatar

struct AvatarRing: View {
    let image: NSImage
    let progress: Double
    let accent: Color

    private let size: CGFloat = 27
    private let lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size - 7, height: size - 7)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.28), value: progress)
        .help("今天已完成 \(Int((progress * 100).rounded()))%")
    }
}

// MARK: - Row

struct TodoRow: View {
    @EnvironmentObject private var store: TodoStore
    let item: Todo
    var now: Date = Date()

    @State private var hover = false
    @State private var showEditor = false

    private var isOverdue: Bool {
        guard let due = item.dueAt else { return false }
        return !item.done && due < now
    }

    private var dueColor: Color {
        guard let due = item.dueAt else { return .secondary }
        if item.done { return .secondary }
        if due < now { return TodoStyle.overdue }
        if Calendar.current.isDateInToday(due) || due.timeIntervalSince(now) < 86_400 {
            return TodoStyle.soon
        }
        return store.accent
    }

    private var stripeColor: Color {
        if let person = item.people.first {
            return PersonPalette.color(for: person)
        }
        return store.accent
    }

    private var hasMeta: Bool {
        item.dueAt != nil || !item.people.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(stripeColor.opacity(item.done ? 0.3 : 1))
                .frame(width: 3)
                .padding(.vertical, 7)

            HStack(alignment: .top, spacing: 8) {
                checkButton
                    .padding(.top, 1.5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.app(size: 13, weight: item.done ? .regular : .medium))
                        .strikethrough(item.done, color: .secondary)
                        .foregroundStyle(item.done ? Color.secondary.opacity(0.7) : Color.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if hasMeta {
                        metaRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { showEditor = true }
                .help("点击编辑时间、提醒和相关人")

                deleteButton
                    .padding(.top, 1.5)
                    .opacity(hover ? 1 : 0)
                    .allowsHitTesting(hover)
            }
            .padding(.leading, 8)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        )
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                hover = inside
            }
        }
        .contextMenu {
            Button {
                showEditor = true
            } label: {
                Label("编辑详情", systemImage: "pencil")
            }

            Button {
                withAnimation(.easeOut(duration: 0.16)) { store.toggle(item) }
            } label: {
                Label(
                    item.done ? "标记为未完成" : "标记完成",
                    systemImage: item.done ? "arrow.uturn.backward.circle" : "checkmark.circle"
                )
            }

            if item.dueAt != nil {
                Button {
                    store.update(
                        item,
                        title: item.title,
                        dueAt: nil,
                        reminderLead: nil,
                        mentions: item.people
                    )
                } label: {
                    Label("清除截止时间", systemImage: "clock.badge.xmark")
                }
            }

            Divider()

            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.16)) { store.delete(item) }
            } label: {
                Label("删除待办", systemImage: "trash")
            }
        }
        .popover(isPresented: $showEditor, arrowEdge: .bottom) {
            TodoEditorPopover(
                item: item,
                accent: store.accent,
                onSave: { title, due, lead, people in
                    showEditor = false
                    withAnimation(.easeOut(duration: 0.18)) {
                        store.update(
                            item,
                            title: title,
                            dueAt: due,
                            reminderLead: lead,
                            mentions: people
                        )
                    }
                    if lead != nil, let due, due > Date() {
                        ReminderCenter.shared.requestAccessWithAlert()
                    }
                },
                onCancel: {
                    showEditor = false
                }
            )
        }
    }

    private var rowBackground: Color {
        if item.done {
            return stripeColor.opacity(hover ? 0.05 : 0.022)
        }
        return stripeColor.opacity(hover ? 0.10 : 0.045)
    }

    private var checkButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { store.toggle(item) }
        } label: {
            ZStack {
                Circle()
                    .fill(item.done ? store.accent : stripeColor.opacity(hover ? 0.15 : 0.05))

                Circle()
                    .strokeBorder(
                        item.done ? store.accent : stripeColor.opacity(hover ? 0.8 : 0.45),
                        lineWidth: 1.3
                    )

                if item.done {
                    Image(systemName: "checkmark")
                        .font(.app(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(item.done ? "标记为未完成" : "标记完成")
    }

    private var deleteButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { store.delete(item) }
        } label: {
            Image(systemName: "xmark")
                .font(.app(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("删除待办")
    }

    private var metaRow: some View {
        HStack(spacing: 4) {
            if let due = item.dueAt {
                dueChip(due)
            }

            ForEach(Array(item.people.prefix(2).enumerated()), id: \.offset) { _, person in
                personChip(person)
            }

            if item.people.count > 2 {
                Text("+\(item.people.count - 2)")
                    .font(.app(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
            }

            Spacer(minLength: 0)
        }
    }

    private func dueChip(_ due: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: isOverdue ? "exclamationmark.circle.fill" : "clock")
                .font(.app(size: 8, weight: .semibold))

            Text(DateUtil.todoDueLabel(due, now: now))
                .font(.app(size: 9.5, weight: .semibold))
                .lineLimit(1)

            if item.hasReminder, !item.done {
                Image(systemName: "bell.fill")
                    .font(.app(size: 7, weight: .semibold))
            }
        }
        .foregroundStyle(dueColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(dueColor.opacity(item.done ? 0.06 : 0.12)))
    }

    private func personChip(_ person: String) -> some View {
        let color = PersonPalette.color(for: person)
        let name = person.count > 9 ? String(person.prefix(9)) + "…" : person

        return HStack(spacing: 1) {
            Text("@")
                .font(.app(size: 8.5, weight: .semibold))
                .opacity(0.7)

            Text(name)
                .font(.app(size: 9.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color.opacity(item.done ? 0.55 : 1))
        .padding(.horizontal, 5.5)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(color.opacity(item.done ? 0.04 : 0.10)))
    }
}

// MARK: - Person colors

enum PersonPalette {
    private static let colors: [Color] = [
        Color(red: 0.14, green: 0.44, blue: 0.88),
        Color(red: 0.54, green: 0.31, blue: 0.85),
        Color(red: 0.06, green: 0.57, blue: 0.43),
        Color(red: 0.83, green: 0.31, blue: 0.50),
        Color(red: 0.05, green: 0.58, blue: 0.72),
        Color(red: 0.58, green: 0.43, blue: 0.16)
    ]

    static func color(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(sum) % colors.count]
    }
}

enum TodoStyle {
    static let overdue = Color(red: 0.84, green: 0.21, blue: 0.21)
    static let soon = Color(red: 0.82, green: 0.45, blue: 0.07)
}

enum ReminderChoice {
    struct Option: Identifiable {
        let id: Int
        let title: String
    }

    static let options: [Option] = [
        Option(id: -1, title: "不提醒"),
        Option(id: 0, title: "准时提醒"),
        Option(id: 10, title: "提前 10 分钟"),
        Option(id: 60, title: "提前 1 小时")
    ]

    static func label(for value: Int) -> String {
        options.first(where: { $0.id == value })?.title ?? "提前 \(value) 分钟"
    }
}

struct SchedulePopover: View {
    @Binding var date: Date
    @Binding var reminderLead: Int
    let accent: Color
    let onClear: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("截止时间", systemImage: "clock")
                    .font(.app(size: 11.5, weight: .semibold))

                Spacer()

                Button("清除", action: onClear)
                    .buttonStyle(.plain)
                    .font(.app(size: 10))
                    .foregroundStyle(.secondary)
            }

            DatePicker(
                "",
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .font(.app(size: 11.5))

            HStack(spacing: 6) {
                presetButton("1 小时后") {
                    date = DateUtil.todoOneHourLater()
                }
                presetButton("明天 9:00") {
                    date = DateUtil.todoTomorrowMorning()
                }
                Spacer()
            }

            Divider()

            Picker("提醒", selection: $reminderLead) {
                ForEach(ReminderChoice.options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .font(.app(size: 11.5))

            HStack {
                Text("到点会通过系统通知提醒你")
                    .font(.app(size: 9))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("完成", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 268)
        .tint(accent)
        .onExitCommand(perform: onDone)
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(Color.primary.opacity(0.055)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct TodoEditorPopover: View {
    let item: Todo
    let accent: Color
    let onSave: (String, Date?, Int?, [String]) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var peopleText: String
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var reminderLead: Int
    @FocusState private var titleFocused: Bool

    init(
        item: Todo,
        accent: Color,
        onSave: @escaping (String, Date?, Int?, [String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.item = item
        self.accent = accent
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: item.title)
        _peopleText = State(initialValue: item.people.joined(separator: " "))
        _hasDue = State(initialValue: item.dueAt != nil)
        _dueDate = State(initialValue: item.dueAt ?? DateUtil.defaultTodoDueDate())
        _reminderLead = State(initialValue: item.reminderLead ?? -1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("编辑待办")
                    .font(.app(size: 12.5, weight: .semibold))

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.app(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            TextField("待办内容", text: $title)
                .textFieldStyle(.plain)
                .font(.app(size: 12.5, weight: .medium))
                .focused($titleFocused)
                .onSubmit(save)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            HStack(spacing: 6) {
                Image(systemName: "at")
                    .font(.app(size: 10, weight: .semibold))
                    .foregroundStyle(accent)

                TextField("相关人，用逗号分隔", text: $peopleText)
                    .textFieldStyle(.plain)
                    .font(.app(size: 11.5))
                    .onSubmit(save)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack(spacing: 8) {
                Toggle("截止时间", isOn: $hasDue.animation(.easeOut(duration: 0.15)))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.app(size: 11.5))

                Spacer()

                if hasDue {
                    Text(DateUtil.todoDueLabel(dueDate))
                        .font(.app(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
            .onChange(of: hasDue) { _, enabled in
                guard enabled else { return }
                if item.dueAt == nil {
                    dueDate = DateUtil.defaultTodoDueDate()
                }
                if reminderLead < 0 {
                    reminderLead = 0
                }
            }

            if hasDue {
                DatePicker(
                    "",
                    selection: $dueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.field)
                .font(.app(size: 11.5))

                HStack {
                    Text("提醒")
                        .font(.app(size: 11.5))

                    Spacer()

                    Picker("", selection: $reminderLead) {
                        ForEach(ReminderChoice.options) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                    .font(.app(size: 11.5))
                }
            }

            Divider()

            HStack(spacing: 8) {
                if hasDue && reminderLead >= 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.app(size: 7.5))

                        Text("到点通知")
                            .font(.app(size: 9))
                    }
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.app(size: 10.5))
                    .foregroundStyle(.secondary)

                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 292)
        .tint(accent)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                titleFocused = true
            }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let people = peopleText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； "))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let due = hasDue ? dueDate : nil
        let lead = hasDue && reminderLead >= 0 ? reminderLead : nil
        onSave(cleanTitle, due, lead, people)
    }
}
