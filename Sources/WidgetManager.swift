import AppKit
import Combine
import SwiftUI

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case todo
    case countdown
    case calendar
    case pomodoro
    case today
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: return "待办"
        case .countdown: return "倒数日"
        case .calendar: return "日历"
        case .pomodoro: return "番茄钟"
        case .today: return "今日概览"
        case .weather: return "天气"
        }
    }

    var subtitle: String {
        switch self {
        case .todo: return "任务清单与完成进度"
        case .countdown: return "重要日子的剩余天数"
        case .calendar: return "农历、节假日与调休"
        case .pomodoro: return "专注计时与今日统计"
        case .today: return "日期、农历、待办与专注一屏看完"
        case .weather: return "实时天气与未来三日预报"
        }
    }

    var symbol: String {
        switch self {
        case .todo: return "checklist"
        case .countdown: return "hourglass"
        case .calendar: return "calendar"
        case .pomodoro: return "timer"
        case .today: return "sun.min"
        case .weather: return "cloud.sun"
        }
    }

    static let cardWidth: CGFloat = 320
    static let shadowPadding: CGFloat = 16

    var width: CGFloat { WidgetKind.cardWidth }

    /// 以下尺寸均指卡片本身，不含卡片四周 16pt 的投影留白。
    var initialHeight: CGFloat {
        switch self {
        case .todo: return 246
        case .countdown: return 226
        case .calendar: return 298
        case .pomodoro: return 298
        case .today: return 306
        case .weather: return 336
        }
    }

    /// 最小卡片尺寸，保证标题、列表与输入区都不被挤掉。
    var minSize: CGSize {
        switch self {
        case .todo: return CGSize(width: 280, height: 224)
        case .countdown: return CGSize(width: 260, height: 210)
        case .calendar: return CGSize(width: 260, height: 298)
        case .pomodoro: return CGSize(width: 260, height: 268)
        case .today: return CGSize(width: 268, height: 236)
        case .weather: return CGSize(width: 252, height: 268)
        }
    }

    var maxSize: CGSize { CGSize(width: 528, height: 728) }

    var windowInset: CGFloat { WidgetKind.shadowPadding * 2 }

    func windowSize(for cardSize: CGSize) -> CGSize {
        CGSize(width: cardSize.width + windowInset, height: cardSize.height + windowInset)
    }

    func cardSize(for windowSize: CGSize) -> CGSize {
        CGSize(width: windowSize.width - windowInset, height: windowSize.height - windowInset)
    }
}

struct WidgetLayout: Codable {
    var enabled: Bool = false
    var x: Double?
    var top: Double?
    var width: Double?
    var height: Double?
}

/// 默认摆放的纯计算：卡片沿同一条左边缘自上而下排成一列，
/// 一列放不下时换到右侧新列，保证多组件同时出现时排列整齐。
enum WidgetPlacement {
    static func columnFrames(
        cards: [CGSize],
        area: NSRect,
        padding: CGFloat,
        originLeft: CGFloat?,
        originTop: CGFloat?,
        edgeGap: CGFloat,
        topGap: CGFloat,
        rowGap: CGFloat,
        columnGap: CGFloat,
        bottomReserve: CGFloat
    ) -> [NSRect] {
        var frames: [NSRect] = []
        let startLeft = originLeft ?? (area.minX + edgeGap)
        let startTop = originTop ?? (area.maxY - topGap)
        var cardLeft = startLeft
        var cardTop = startTop
        var columnWidth: CGFloat = 0

        for (index, card) in cards.enumerated() {
            if index > 0, cardTop - card.height < area.minY + bottomReserve {
                cardLeft += columnWidth + columnGap
                cardTop = startTop
                columnWidth = 0
            }

            let windowSize = CGSize(width: card.width + padding * 2, height: card.height + padding * 2)
            frames.append(NSRect(
                x: cardLeft - padding,
                y: cardTop + padding - windowSize.height,
                width: windowSize.width,
                height: windowSize.height
            ))

            cardTop -= card.height + rowGap
            columnWidth = max(columnWidth, card.width)
        }

        return frames
    }
}

final class WidgetManager: ObservableObject {
    let store: TodoStore

    @Published private(set) var enabledKinds: Set<WidgetKind> = []
    @Published private(set) var deskVisible = true

    private(set) var windows: [WidgetKind: WidgetWindow] = [:]
    /// 日历点年份弹出的全年总览，临时窗口，不进布局也不写盘。
    private var yearWindow: WidgetWindow?
    private var layouts: [WidgetKind: WidgetLayout] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var started = false
    private var positionsClamped = false
    /// 本次启动里刚被自动启用的组件，等默认列整理完再单独摆放。
    private var pendingSeededKinds: [WidgetKind] = []
    private var moveObservers: [WidgetKind: NSObjectProtocol] = [:]
    private var pendingPersistWork: [WidgetKind: DispatchWorkItem] = [:]

    private let layoutsKey = "desktodo.widgets.v1"
    private let leftTopKey = "desktodo.layout.leftTop.v5"
    private let pomodoroSeedKey = "desktodo.pomodoro.seeded.v1"
    private let overviewSeedKey = "wedesk.widgets.overview.seeded.v1"

    // MARK: - Default placement metrics（以下数值均指卡片本身，不含投影留白）

    /// 默认列的卡片左缘与屏幕左缘的距离。
    private static let edgeGap: CGFloat = 16
    /// 默认列的第一张卡片上缘与可视区顶部的距离。
    private static let topGap: CGFloat = 12
    /// 纵向堆叠时两张卡片之间的距离。
    private static let rowGap: CGFloat = 14
    /// 屏幕高度放不下时，换到下一列的横向距离。
    private static let columnGap: CGFloat = 20
    /// 卡片底部至少保留这么多可视高度，否则换列。
    private static let bottomReserve: CGFloat = 40

    var onOpenLibrary: (() -> Void)?

    init(store: TodoStore) {
        self.store = store
        loadLayouts()

        store.$pinned
            .removeDuplicates()
            .sink { [weak self] pinned in
                guard let self else { return }
                for window in self.windows.values {
                    window.applyPin(pinned)
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else { return }
        started = true
        seedPomodoroIfNeeded()
        seedOverviewWidgetsIfNeeded()
        guard !enabledKinds.isEmpty else { return }

        // 新启用的卡片留到默认列整理完以后再创建，避免被误判成重叠而重排全部位置。
        for kind in WidgetKind.allCases where enabledKinds.contains(kind) && !pendingSeededKinds.contains(kind) {
            _ = window(for: kind)
        }

        if !UserDefaults.standard.bool(forKey: leftTopKey) {
            UserDefaults.standard.set(true, forKey: leftTopKey)
            applyLeftTopLayout()
        } else if positionsClamped || hasOverlappingWindows() {
            applyLeftTopLayout()
        }

        placeSeededWidgets()

        guard deskVisible else { return }
        for kind in WidgetKind.allCases where enabledKinds.contains(kind) {
            windows[kind]?.orderFrontRegardless()
        }
        windows[.todo]?.orderFrontRegardless()
    }

    func isEnabled(_ kind: WidgetKind) -> Bool {
        enabledKinds.contains(kind)
    }

    func window(for kind: WidgetKind) -> WidgetWindow? {
        if let existing = windows[kind] {
            return existing
        }
        return createWindow(for: kind)
    }

    func setEnabled(_ kind: WidgetKind, enabled: Bool) {
        guard enabled != enabledKinds.contains(kind) else { return }

        if enabled {
            if layouts[kind] == nil {
                layouts[kind] = WidgetLayout()
            }
            layouts[kind]?.enabled = true
            enabledKinds.insert(kind)
            persistLayouts()

            guard let window = window(for: kind) else { return }
            alignIntoColumn(window, kind: kind)
            persistFrame(kind)
            if deskVisible {
                window.orderFrontRegardless()
            } else {
                showAll()
            }
        } else {
            layouts[kind]?.enabled = false
            enabledKinds.remove(kind)
            windows[kind]?.orderOut(nil)
            persistLayouts()
            persistFrame(kind)
            restackColumn()
        }
    }

    /// 移除一张卡片后，剩下的卡片自动收拢成一列：沿用剩余卡片最靠左、最靠上的边线，
    /// 纵向按默认间距补齐，不留空档，也不会跳到屏幕角落。
    private func restackColumn() {
        let kinds = placementOrder
        let padding = WidgetKind.shadowPadding
        let frames = kinds.compactMap { windows[$0]?.frame }
        guard frames.count > 1 else { return }

        let originLeft = frames.map { $0.minX + padding }.min() ?? padding
        let originTop = frames.map { $0.maxY - padding }.max() ?? padding
        let cards = kinds.compactMap { kind -> CGSize? in
            windows[kind].map { kind.cardSize(for: $0.frame.size) }
        }
        let slots = columnFrames(cards: cards, originLeft: originLeft, originTop: originTop)

        for (index, kind) in kinds.enumerated() where index < slots.count {
            guard let window = windows[kind] else { continue }
            let slot = slots[index]
            if abs(window.frame.minX - slot.minX) < 1 && abs(window.frame.maxY - slot.maxY) < 1 {
                continue
            }
            window.setFrame(
                NSRect(origin: NSPoint(x: slot.minX, y: slot.maxY - slot.height), size: slot.size),
                display: true,
                animate: true
            )
            persistFrame(kind)
        }
    }

    func remove(_ kind: WidgetKind) {
        setEnabled(kind, enabled: false)
    }

    func showAll() {
        guard !enabledKinds.isEmpty else {
            onOpenLibrary?()
            return
        }

        deskVisible = true
        for kind in WidgetKind.allCases where enabledKinds.contains(kind) {
            window(for: kind)?.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        let keyWindow = windows[.todo] ?? WidgetKind.allCases.compactMap { windows[$0] }.first
        keyWindow?.makeKey()
    }

    func hideAll() {
        deskVisible = false
        closeYearOverview()
        for window in windows.values {
            window.orderOut(nil)
        }
        NSApp.deactivate()
    }

    // MARK: - 全年总览

    /// 日历卡上的年份是入口：点开是全年，再点一次收起。
    func toggleYearOverview() {
        if yearWindow == nil {
            showYearOverview()
        } else {
            closeYearOverview()
        }
    }

    func closeYearOverview() {
        guard let yearWindow else { return }
        yearWindow.orderOut(nil)
        self.yearWindow = nil
    }

    private func showYearOverview() {
        let card = YearOverviewView.cardSize
        let padding = WidgetKind.shadowPadding
        let windowSize = CGSize(width: card.width + padding * 2, height: card.height + padding * 2)

        let panel = WidgetWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        // 卡片留在桌面层，但这是用户主动点开的临时面板，得浮在前面才看得见。
        panel.applyPin(false)

        let calendar = Calendar.current
        let root = AnyView(
            YearOverviewView(
                year: calendar.component(.year, from: store.dayAnchor),
                onPickMonth: { [weak self] monthStart in
                    guard let self else { return }
                    self.store.calendarFocusMonth = monthStart
                    self.closeYearOverview()
                    if self.deskVisible {
                        self.window(for: .calendar)?.orderFrontRegardless()
                    }
                },
                onClose: { [weak self] in
                    self?.closeYearOverview()
                }
            )
            .environmentObject(store)
        )
        panel.contentView = NSHostingView(rootView: root)

        let anchor = window(for: .calendar)?.frame ?? .zero
        let area = visibleArea(containing: anchor)
        let topLeftX = area.midX - windowSize.width / 2
        let topLeftY = area.maxY - 28
        panel.setFrameTopLeftPoint(NSPoint(x: topLeftX, y: topLeftY))

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        yearWindow = panel
    }

    func toggleAll() {
        guard !enabledKinds.isEmpty else {
            onOpenLibrary?()
            return
        }

        if deskVisible {
            hideAll()
        } else {
            showAll()
        }
    }

    func resetPositions() {
        guard !enabledKinds.isEmpty else { return }
        for kind in WidgetKind.allCases where enabledKinds.contains(kind) {
            _ = window(for: kind)
        }
        applyLeftTopLayout()
        if deskVisible {
            for kind in WidgetKind.allCases where enabledKinds.contains(kind) {
                windows[kind]?.orderFrontRegardless()
            }
        }
    }

    private func seedPomodoroIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: pomodoroSeedKey) else { return }
        UserDefaults.standard.set(true, forKey: pomodoroSeedKey)
        guard layouts[.pomodoro]?.enabled != true else { return }

        layouts[.pomodoro] = WidgetLayout(enabled: true, x: nil, top: nil)
        enabledKinds.insert(.pomodoro)
        persistLayouts()
    }

    /// 今日概览与天气是新上线的两张卡，只自动启用一次；
    /// 用户之后手动关掉就不再自作主张地打开。
    private func seedOverviewWidgetsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: overviewSeedKey) else { return }
        UserDefaults.standard.set(true, forKey: overviewSeedKey)

        var seeded: [WidgetKind] = []
        for kind in [WidgetKind.today, .weather] where layouts[kind]?.enabled != true {
            layouts[kind] = WidgetLayout(enabled: true, x: nil, top: nil)
            enabledKinds.insert(kind)
            seeded.append(kind)
        }
        guard !seeded.isEmpty else { return }
        persistLayouts()
        pendingSeededKinds.append(contentsOf: seeded)
    }

    /// 新卡片接在现有列的末尾；当前列放不下就顺势换到右侧新列，
    /// 全程不改动用户已经摆好的其它卡片位置。
    private func placeSeededWidgets() {
        let kinds = pendingSeededKinds
        pendingSeededKinds.removeAll()

        for kind in kinds {
            guard enabledKinds.contains(kind), let window = windows[kind] ?? window(for: kind) else { continue }
            alignIntoColumn(window, kind: kind)
            persistFrame(kind)
            if deskVisible {
                window.orderFrontRegardless()
            }
        }
    }

    /// 判断是否真的叠在一起：比较卡片本体，不含四周的投影留白。
    private func hasOverlappingWindows() -> Bool {
        let padding = WidgetKind.shadowPadding
        let frames = WidgetKind.allCases.compactMap { windows[$0]?.frame }
            .map { $0.insetBy(dx: padding, dy: padding) }
        for i in frames.indices {
            for j in (i + 1)..<frames.count where frames[i].intersects(frames[j]) {
                return true
            }
        }
        return false
    }

    private func activeVisibleArea() -> NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 与给定矩形重叠最多的屏幕；完全不相交时返回 nil。
    private func visibleArea(overlapping rect: NSRect) -> NSRect? {
        NSScreen.screens.compactMap { screen -> (CGFloat, NSRect)? in
            guard screen.visibleFrame.intersects(rect) else { return nil }
            let overlap = screen.visibleFrame.intersection(rect)
            return (overlap.width * overlap.height, screen.visibleFrame)
        }.max { $0.0 < $1.0 }?.1
    }

    /// 找到真正包含该保存位置的屏幕，避免多显示器场景被误判为越界。
    private func visibleArea(containing rect: NSRect) -> NSRect {
        visibleArea(overlapping: rect) ?? fallbackArea()
    }

    /// 位置彻底丢失时，跟随其它已启用组件所在的那块屏幕，而不是跳到主屏。
    private func fallbackArea() -> NSRect {
        let padding = WidgetKind.shadowPadding
        for kind in WidgetKind.allCases where enabledKinds.contains(kind) {
            guard let layout = layouts[kind], let x = layout.x, let top = layout.top else { continue }
            let height = CGFloat(layout.height ?? Double(kind.initialHeight)) + padding * 2
            let width = CGFloat(layout.width ?? Double(kind.width)) + padding * 2
            let rect = NSRect(x: x, y: top - height, width: width, height: height)
            if let screen = visibleArea(overlapping: rect.insetBy(dx: -padding, dy: -padding)) {
                return screen
            }
        }
        return activeVisibleArea()
    }

    /// 默认摆放锚定的屏幕：以现有卡片所在屏幕为准。
    private func placementArea() -> NSRect {
        let padding = WidgetKind.shadowPadding
        for kind in placementOrder {
            if let frame = windows[kind]?.frame,
               let screen = visibleArea(overlapping: frame.insetBy(dx: padding, dy: padding)) {
                return screen
            }
        }
        return fallbackArea()
    }

    /// 参与默认摆放的组件：已启用且窗口已创建，按固定顺序排列。
    private var placementOrder: [WidgetKind] {
        WidgetKind.allCases.filter { enabledKinds.contains($0) && windows[$0] != nil }
    }

    /// 默认摆放：贴着屏幕左缘，自上而下对齐成一列，共享同一条左边缘。
    private func applyLeftTopLayout() {
        let kinds = placementOrder
        let cards = kinds.compactMap { kind -> CGSize? in
            windows[kind].map { kind.cardSize(for: $0.frame.size) }
        }
        let frames = columnFrames(cards: cards)

        for (index, frame) in frames.enumerated() where index < kinds.count {
            guard let window = windows[kinds[index]] else { continue }
            window.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
            persistFrame(kinds[index])
        }
    }

    /// 新启用的组件接在默认列的最下方，并沿用同一左边缘；放不下时换到下一列。
    private func alignIntoColumn(_ window: NSWindow, kind: WidgetKind) {
        let neighbours = placementOrder.filter { $0 != kind }
        let neighbourFrames = neighbours.compactMap { windows[$0]?.frame }
        guard let first = neighbourFrames.first else {
            applyLeftTopLayout()
            return
        }

        let padding = WidgetKind.shadowPadding
        // 沿用现有列的左边缘与顶端，让新卡片自然接在队列末尾。
        let originLeft = neighbourFrames.map { $0.minX + padding }.min() ?? first.minX + padding
        let originTop = neighbourFrames.map { $0.maxY - padding }.max() ?? first.maxY - padding

        var cards = zip(neighbours, neighbourFrames).map { other, frame in
            other.cardSize(for: frame.size)
        }
        cards.append(kind.cardSize(for: window.frame.size))

        guard let slot = columnFrames(cards: cards, originLeft: originLeft, originTop: originTop).last else {
            return
        }
        window.setFrameTopLeftPoint(NSPoint(x: slot.minX, y: slot.maxY))
    }

    private func columnFrames(
        cards: [CGSize],
        originLeft: CGFloat? = nil,
        originTop: CGFloat? = nil
    ) -> [NSRect] {
        WidgetPlacement.columnFrames(
            cards: cards,
            area: placementArea(),
            padding: WidgetKind.shadowPadding,
            originLeft: originLeft,
            originTop: originTop,
            edgeGap: Self.edgeGap,
            topGap: Self.topGap,
            rowGap: Self.rowGap,
            columnGap: Self.columnGap,
            bottomReserve: Self.bottomReserve
        )
    }

    /// 拖动/移动窗口后延迟落盘，避免逐帧写 UserDefaults。
    private func schedulePersistFrame(_ kind: WidgetKind) {
        pendingPersistWork[kind]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistFrame(kind)
        }
        pendingPersistWork[kind] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func persistFrame(_ kind: WidgetKind) {
        guard let window = windows[kind] else { return }
        if layouts[kind] == nil {
            layouts[kind] = WidgetLayout()
        }
        let cardSize = kind.cardSize(for: window.frame.size)
        layouts[kind]?.x = window.frame.origin.x
        layouts[kind]?.top = window.frame.maxY
        layouts[kind]?.width = cardSize.width
        layouts[kind]?.height = cardSize.height
        layouts[kind]?.enabled = enabledKinds.contains(kind)
        persistLayouts()
    }

    func persistAllFrames() {
        for kind in windows.keys {
            persistFrame(kind)
        }
    }

    // MARK: - Layouts

    private func loadLayouts() {
        if let data = UserDefaults.standard.data(forKey: layoutsKey),
           let decoded = try? JSONDecoder().decode([String: WidgetLayout].self, from: data) {
            var restored: [WidgetKind: WidgetLayout] = [:]
            for kind in WidgetKind.allCases {
                restored[kind] = decoded[kind.rawValue] ?? WidgetLayout()
            }
            layouts = restored
            enabledKinds = Set(WidgetKind.allCases.filter { restored[$0]?.enabled == true })
        } else {
            seedDefaultLayouts()
        }
    }

    private func seedDefaultLayouts() {
        let area = activeVisibleArea()
        let padding = WidgetKind.shadowPadding
        var cardTop = area.maxY - Self.topGap

        for kind in WidgetKind.allCases {
            layouts[kind] = WidgetLayout(
                enabled: true,
                x: area.minX + Self.edgeGap - padding,
                top: cardTop + padding
            )
            cardTop -= kind.initialHeight + Self.rowGap
        }

        enabledKinds = Set(WidgetKind.allCases)
        persistLayouts()
    }

    private func persistLayouts() {
        var encoded: [String: WidgetLayout] = [:]
        for kind in WidgetKind.allCases {
            var layout = layouts[kind] ?? WidgetLayout()
            layout.enabled = enabledKinds.contains(kind)
            encoded[kind.rawValue] = layout
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        UserDefaults.standard.set(data, forKey: layoutsKey)
    }

    // MARK: - Windows

    private func createWindow(for kind: WidgetKind) -> WidgetWindow? {
        let root = AnyView(
            rootView(for: kind)
                .environmentObject(store)
                .environmentObject(store.pomodoro)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.sizingOptions = []

        let layout = layouts[kind] ?? WidgetLayout()
        let cardSize = CGSize(
            width: layout.width.map { min(max(CGFloat($0), kind.minSize.width), kind.maxSize.width) } ?? kind.width,
            height: layout.height.map { min(max(CGFloat($0), kind.minSize.height), kind.maxSize.height) } ?? kind.initialHeight
        )
        let window = WidgetWindow(
            contentRect: NSRect(origin: .zero, size: kind.windowSize(for: cardSize)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.applyPin(store.pinned)
        window.contentView = hosting
        window.kind = kind
        window.onFrameSettled = { [weak self] in
            self?.persistFrame(kind)
        }
        moveObservers[kind] = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.schedulePersistFrame(kind)
        }

        let savedTop = layout.top ?? suggestedTop(in: placementArea())
        let savedX = layout.x ?? suggestedX(for: window, in: placementArea())
        let savedRect = NSRect(
            x: savedX,
            y: savedTop - window.frame.height,
            width: window.frame.width,
            height: window.frame.height
        )
        let area = visibleArea(containing: savedRect)
        let padding = WidgetKind.shadowPadding

        // 允许投影留白探出可视区，只有卡片本体真正离开屏幕时才回收位置。
        let placedX = min(max(savedX, area.minX - padding), area.maxX - window.frame.width + padding)
        let placedTop = min(max(savedTop, area.minY + 120), area.maxY + padding)
        if abs(placedX - savedX) > 1 || abs(placedTop - savedTop) > 1 {
            positionsClamped = true
        }
        window.setFrameTopLeftPoint(NSPoint(x: placedX, y: placedTop))

        windows[kind] = window
        persistFrame(kind)
        return window
    }

    /// 没有保存位置时，沿用默认列：贴屏幕左缘，接在最下方一张卡片之下。
    private func suggestedX(for window: NSWindow, in area: NSRect) -> CGFloat {
        let leftmost = windows.values.map(\.frame.minX).min() ?? (area.minX + Self.edgeGap - WidgetKind.shadowPadding)
        return leftmost
    }

    private func suggestedTop(in area: NSRect) -> CGFloat {
        let padding = WidgetKind.shadowPadding
        guard let lowest = windows.values.map({ $0.frame.minY + padding }).min() else {
            return area.maxY - Self.topGap + padding
        }
        return lowest - Self.rowGap + padding
    }

    private func rootView(for kind: WidgetKind) -> AnyView {
        switch kind {
        case .todo:
            return AnyView(
                ContentView(
                    onHideAll: { [weak self] in
                        self?.hideAll()
                    },
                    onHideSelf: { [weak self] in
                        self?.remove(.todo)
                    },
                    onOpenLibrary: { [weak self] in
                        self?.onOpenLibrary?()
                    },
                    onResetPositions: { [weak self] in
                        self?.resetPositions()
                    },
                    onOpenYearOverview: { [weak self] in
                        self?.toggleYearOverview()
                    }
                )
            )

        case .countdown:
            return AnyView(
                CountdownWidgetRoot(
                    onHide: { [weak self] in
                        self?.remove(.countdown)
                    }
                )
            )

        case .calendar:
            return AnyView(
                CalendarWidgetRoot(
                    onHide: { [weak self] in
                        self?.closeYearOverview()
                        self?.remove(.calendar)
                    },
                    onOpenYear: { [weak self] in
                        self?.toggleYearOverview()
                    }
                )
            )

        case .pomodoro:
            return AnyView(
                PomodoroWidgetRoot(
                    onHide: { [weak self] in
                        self?.remove(.pomodoro)
                    }
                )
            )

        case .today:
            return AnyView(
                TodayWidgetRoot(
                    onHide: { [weak self] in
                        self?.remove(.today)
                    }
                )
            )

        case .weather:
            return AnyView(
                WeatherWidgetRoot(
                    onHide: { [weak self] in
                        self?.remove(.weather)
                    }
                )
            )
        }
    }
}
