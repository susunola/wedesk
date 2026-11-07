import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Todo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var done: Bool = false
    var createdAt: Date = Date()
    var dueAt: Date? = nil
    var reminderLead: Int? = nil
    var mentions: [String]? = nil

    var people: [String] { mentions ?? [] }

    var hasReminder: Bool {
        dueAt != nil && reminderLead != nil
    }
}

enum MentionParser {
    private static let regex = try! NSRegularExpression(
        pattern: "@([\\p{L}\\p{N}_·\\-]+)"
    )

    static func extract(from text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var result: [String] = []

        for match in regex.matches(in: text, range: range) {
            guard let tokenRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(name)
        }
        return result
    }

    static func sanitize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let name = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(name)
        }
        return result
    }
}

struct Countdown: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var date: Date
}

final class TodoStore: ObservableObject {
    let pomodoro = PomodoroEngine()

    @Published private(set) var items: [Todo] = []
    @Published private(set) var countdowns: [Countdown] = []
    @Published private(set) var pinned: Bool = true
    @Published private(set) var accentIndex: Int = 0
    @Published private(set) var showAvatar: Bool = true
    @Published private(set) var avatarImage: NSImage?
    @Published private(set) var hotKey = HotKeySetting.default
    @Published private(set) var hotKeyConflict = false
    /// 卡片底面材质与通透度，所有便签共用一套设置。
    @Published private(set) var cardMaterial: CardMaterial = .solid
    @Published private(set) var glassClarity: Double = 0.55
    /// 卡片里的"今天"都锚定这个时间。跨午夜或睡眠醒来后由下面的看门狗刷新，
    /// 所有观察 store 的卡片会一起重算，日历高亮不会再停在开机那天。
    @Published private(set) var dayAnchor = Date()

    private let itemsKey = "desktodo.items.v1"
    private let countdownsKey = "desktodo.countdowns.v1"
    private let pinnedKey = "desktodo.pinned.v1"
    private let accentKey = "desktodo.accent.v1"
    private let avatarOnKey = "desktodo.avatar.on.v1"
    private let avatarPathKey = "desktodo.avatar.path.v1"
    private let hotKeyKey = "desktodo.hotkey.v1"
    private let cardMaterialKey = "wedesk.card.material.v1"
    private let glassClarityKey = "wedesk.card.clarity.v1"

    private var dayTimer: Timer?
    private var dayChangeObserver: NSObjectProtocol?

    init() {
        pinned = UserDefaults.standard.object(forKey: pinnedKey) as? Bool ?? true
        accentIndex = UserDefaults.standard.object(forKey: accentKey) as? Int ?? 0
        showAvatar = UserDefaults.standard.object(forKey: avatarOnKey) as? Bool ?? true
        cardMaterial = CardMaterial(rawValue: UserDefaults.standard.integer(forKey: cardMaterialKey)) ?? .solid
        glassClarity = UserDefaults.standard.object(forKey: glassClarityKey) as? Double ?? 0.55
        if let saved = UserDefaults.standard.object(forKey: hotKeyKey) as? [Int],
           saved.count == 2 {
            hotKey = HotKeySetting(keyCode: UInt32(saved[0]), modifiers: UInt32(saved[1]))
        }
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([Todo].self, from: data) {
            items = decoded
        }
        if let data = UserDefaults.standard.data(forKey: countdownsKey),
           let decoded = try? JSONDecoder().decode([Countdown].self, from: data) {
            countdowns = decoded.sorted { $0.date < $1.date }
        }
        avatarImage = Self.loadAvatarImage()
        startDayRolloverWatch()
    }

    // MARK: - Day rollover

    private func startDayRolloverWatch() {
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDayAnchor()
        }

        // 睡眠期间系统通知可能整段错过，所以再挂一个每分钟的心跳兜底。
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshDayAnchor()
        }
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer
    }

    private func refreshDayAnchor() {
        let now = Date()
        guard !Calendar.current.isDate(now, inSameDayAs: dayAnchor) else { return }
        dayAnchor = now
    }

    var accent: Color {
        Palette.accent(at: accentIndex).color
    }

    var accentName: String {
        Palette.accent(at: accentIndex).name
    }

    func setAccent(_ index: Int) {
        guard index != accentIndex, index >= 0, index < Palette.accents.count else { return }
        accentIndex = index
        UserDefaults.standard.set(index, forKey: accentKey)
    }

    // MARK: - 卡片材质

    func setCardMaterial(_ value: CardMaterial) {
        guard value != cardMaterial else { return }
        cardMaterial = value
        UserDefaults.standard.set(value.rawValue, forKey: cardMaterialKey)
    }

    /// 通透度 0（乳白）到 1（最透）。
    func setGlassClarity(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        guard abs(clamped - glassClarity) > 0.001 else { return }
        glassClarity = clamped
        UserDefaults.standard.set(clamped, forKey: glassClarityKey)
    }

    // MARK: - Avatar

    func setShowAvatar(_ value: Bool) {
        guard value != showAvatar else { return }
        showAvatar = value
        UserDefaults.standard.set(value, forKey: avatarOnKey)
    }

    func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "使用这张图"
        panel.message = "选择一张图片作为左上角头像"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAvatar(from: url)
    }

    func resetAvatar() {
        UserDefaults.standard.removeObject(forKey: avatarPathKey)
        avatarImage = Self.loadAvatarImage()
        setShowAvatar(true)
    }

    private func importAvatar(from url: URL) {
        let fileManager = FileManager.default
        let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WeDesk", isDirectory: true)
        try? fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let destination = supportDir.appendingPathComponent("avatar.\(ext)")
        try? fileManager.removeItem(at: destination)

        guard (try? fileManager.copyItem(at: url, to: destination)) != nil,
              let image = NSImage(contentsOf: destination) else { return }

        UserDefaults.standard.set(destination.path, forKey: avatarPathKey)
        avatarImage = image
        setShowAvatar(true)
    }

    private static func loadAvatarImage() -> NSImage? {
        if let path = UserDefaults.standard.string(forKey: "desktodo.avatar.path.v1"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        if let url = Bundle.main.url(forResource: "avatar", withExtension: "jpg") {
            return NSImage(contentsOf: url)
        }
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/avatar.jpg")
        if FileManager.default.fileExists(atPath: dev.path) {
            return NSImage(contentsOf: dev)
        }
        return nil
    }

    var remaining: Int {
        items.reduce(0) { $0 + ($1.done ? 0 : 1) }
    }

    var completed: Int {
        items.reduce(0) { $0 + ($1.done ? 1 : 0) }
    }

    var knownPeople: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            for person in item.people where !seen.contains(person) {
                seen.insert(person)
                result.append(person)
            }
        }
        return result
    }

    @discardableResult
    func add(
        _ title: String,
        dueAt: Date? = nil,
        reminderLead: Int? = nil,
        mentions: [String] = []
    ) -> Todo? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsed = MentionParser.sanitize(mentions.isEmpty ? MentionParser.extract(from: trimmed) : mentions)
        let due = Self.normalizedDue(dueAt)
        var todo = Todo(title: trimmed)
        todo.dueAt = due
        todo.reminderLead = due == nil ? nil : reminderLead.flatMap { $0 >= 0 ? $0 : nil }
        todo.mentions = parsed.isEmpty ? nil : parsed

        items.insert(todo, at: 0)
        persistItems()
        scheduleReminder(for: todo)
        return todo
    }

    func toggle(_ item: Todo) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].done.toggle()
        persistItems()
        scheduleReminder(for: items[index])
    }

    func delete(_ item: Todo) {
        ReminderCenter.shared.cancel(todo: item)
        items.removeAll { $0.id == item.id }
        persistItems()
    }

    func update(
        _ item: Todo,
        title: String,
        dueAt: Date?,
        reminderLead: Int?,
        mentions: [String]
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        let due = Self.normalizedDue(dueAt)
        let people = MentionParser.sanitize(mentions)

        items[index].title = trimmed
        items[index].dueAt = due
        items[index].reminderLead = due == nil ? nil : reminderLead.flatMap { $0 >= 0 ? $0 : nil }
        items[index].mentions = people.isEmpty ? nil : people
        persistItems()
        scheduleReminder(for: items[index])
    }

    func clearCompleted() {
        for item in items where item.done {
            ReminderCenter.shared.cancel(todo: item)
        }
        items.removeAll { $0.done }
        persistItems()
    }

    func syncReminders() {
        ReminderCenter.shared.sync(items: items)
    }

    private func scheduleReminder(for item: Todo) {
        if item.done || item.dueAt == nil || item.reminderLead == nil {
            ReminderCenter.shared.cancel(todo: item)
        } else {
            ReminderCenter.shared.schedule(todo: item)
        }
    }

    private static func normalizedDue(_ date: Date?) -> Date? {
        guard let date else { return nil }
        let calendar = Calendar.current
        return calendar.date(bySetting: .second, value: 0, of: date) ?? date
    }

    // MARK: - Calendar linkage

    /// 有未完成待办的日期（含逾期），供日历小组件打点。
    var pendingTodoDays: Set<Date> {
        let calendar = Calendar.current
        return Set(
            items.compactMap { item -> Date? in
                guard !item.done, let due = item.dueAt else { return nil }
                return calendar.startOfDay(for: due)
            }
        )
    }

    func pendingTodos(on date: Date) -> [Todo] {
        let calendar = Calendar.current
        return items
            .filter { !$0.done && calendar.isDate($0.dueAt ?? .distantPast, inSameDayAs: date) }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    /// 今日概览清单：今天到期的 + 所有逾期未完成，按到期时间排序。
    var todayAgenda: [Todo] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return items
            .filter { item in
                guard !item.done, let due = item.dueAt else { return false }
                return calendar.startOfDay(for: due) <= today
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    // MARK: - Countdowns

    var nextCountdown: Countdown? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return countdowns
            .filter { calendar.startOfDay(for: $0.date) >= today }
            .min { $0.date < $1.date }
    }

    var upcomingCountdownDays: Set<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return Set(
            countdowns
                .map { calendar.startOfDay(for: $0.date) }
                .filter { $0 >= today }
        )
    }

    func addCountdown(_ title: String, on date: Date) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        countdowns.append(Countdown(title: trimmed, date: Calendar.current.startOfDay(for: date)))
        countdowns.sort { $0.date < $1.date }
        persistCountdowns()
    }

    func deleteCountdown(_ item: Countdown) {
        countdowns.removeAll { $0.id == item.id }
        persistCountdowns()
    }

    private func persistCountdowns() {
        guard let data = try? JSONEncoder().encode(countdowns) else { return }
        UserDefaults.standard.set(data, forKey: countdownsKey)
    }

    func setPinned(_ value: Bool) {
        guard value != pinned else { return }
        pinned = value
        UserDefaults.standard.set(value, forKey: pinnedKey)
    }

    func applyHotKey(_ setting: HotKeySetting, conflict: Bool) {
        hotKey = setting
        hotKeyConflict = conflict
        guard !conflict else { return }
        UserDefaults.standard.set([Int(setting.keyCode), Int(setting.modifiers)], forKey: hotKeyKey)
    }

    func resetHotKey() {
        applyHotKey(.default, conflict: false)
    }

    private func persistItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: itemsKey)
    }
}
