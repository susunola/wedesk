import AppKit
import EventKit
import SwiftUI

// MARK: - Model

/// 苹果日历（系统日历 App）里的一条日程。WeDesk 只读，绝不写入或改动。
struct SystemEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let tint: Color

    var timeText: String {
        isAllDay ? "全天" : DateUtil.timeOnly(start)
    }
}

enum SystemCalendarAccess: Equatable {
    /// 还没问过用户
    case undetermined
    /// 可以读日程
    case granted
    /// 只给了写入权限，读不到内容
    case writeOnly
    /// 被拒绝或受管控
    case blocked

    var hintText: String {
        switch self {
        case .undetermined: return "可读取苹果日历的日程"
        case .granted: return ""
        case .writeOnly: return "只授权了写入，读不到日程"
        case .blocked: return "日历权限已关闭"
        }
    }
}

// MARK: - Store

/// 苹果日历的只读入口。首次展开某天时才申请权限，之后按天取日程。
final class SystemCalendarStore: ObservableObject {
    static let shared = SystemCalendarStore()

    @Published private(set) var access: SystemCalendarAccess = .undetermined
    @Published private(set) var events: [SystemEvent] = []
    @Published private(set) var isBusy = false

    private let store = EKEventStore()
    /// 上一次查询的那天；授权回来后补查。
    private var requestedDay: Date?

    private init() {
        refreshAccess()
    }

    func refreshAccess() {
        access = Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    /// 当天日程。未授权时只记下来，等用户点了"允许"再补查。
    func load(_ date: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        requestedDay = day

        guard access == .granted else {
            if access != .undetermined { events = [] }
            return
        }
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(withStart: day, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .map(Self.event(from:))
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title < rhs.title
            }
    }

    func requestAccess() {
        guard access == .undetermined, !isBusy else { return }
        isBusy = true
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                self.refreshAccess()
                if let day = self.requestedDay { self.load(day) }
            }
        }
    }

    /// 被拒绝后只能回系统设置里手动打开。
    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func map(_ status: EKAuthorizationStatus) -> SystemCalendarAccess {
        switch status {
        case .fullAccess, .authorized: return .granted
        case .writeOnly: return .writeOnly
        case .notDetermined: return .undetermined
        default: return .blocked
        }
    }

    private static func event(from event: EKEvent) -> SystemEvent {
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SystemEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: title.isEmpty ? "（无标题）" : title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            tint: Color(nsColor: event.calendar.color)
        )
    }
}
