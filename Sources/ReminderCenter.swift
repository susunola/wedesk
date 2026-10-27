import AppKit
import Foundation
import UserNotifications

final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderCenter()

    private let identifierPrefix = "desktodo.todo.reminder."
    private var configured = false
    private var didShowDeniedAlert = false
    private let isAvailable = Bundle.main.bundleIdentifier != nil

    func configure() {
        guard isAvailable, !configured else { return }
        configured = true
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAccess(completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else {
            DispatchQueue.main.async { completion?(false) }
            return
        }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.finishAccess(true, completion: completion)
            case .denied:
                self.finishAccess(false, completion: completion)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    self.finishAccess(granted, completion: completion)
                }
            @unknown default:
                self.finishAccess(false, completion: completion)
            }
        }
    }

    func requestAccessWithAlert() {
        requestAccess { granted in
            guard !granted else { return }
            guard !self.didShowDeniedAlert else { return }
            self.didShowDeniedAlert = true

            let alert = NSAlert()
            alert.messageText = "需要开启通知"
            alert.informativeText = "到点提醒需要通过系统通知发送。请在「系统设置 → 通知 → WeDesk」中允许通知。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")

            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                self.openNotificationSettings()
            }
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func notifyPomodoro(title: String, body: String) {
        guard isAvailable else { return }
        requestAccess { granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.threadIdentifier = "desktodo.pomodoro"

            let request = UNNotificationRequest(
                identifier: "desktodo.pomodoro.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.3, repeats: false)
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    func schedule(todo: Todo) {
        guard isAvailable,
              !todo.done,
              let due = todo.dueAt,
              let lead = todo.reminderLead else {
            cancel(todo: todo)
            return
        }

        let now = Date()
        guard due > now else {
            cancel(todo: todo)
            return
        }

        let leadMinutes = max(0, lead)
        let desired = due.addingTimeInterval(-Double(leadMinutes) * 60)
        let fireDate = max(desired, now.addingTimeInterval(2))
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = todo.title
        content.subtitle = leadMinutes == 0
            ? "已到截止时间"
            : "还有 \(Self.leadText(leadMinutes))到期"
        content.body = Self.bodyText(for: todo, due: due)
        content.sound = .default
        content.threadIdentifier = "desktodo.todos"

        let trigger: UNNotificationTrigger
        let interval = fireDate.timeIntervalSinceNow
        if interval < 60 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        } else {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let identifier = identifier(for: todo)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    func cancel(todo: Todo) {
        guard isAvailable else { return }
        let identifier = identifier(for: todo)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func sync(items: [Todo]) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                let stale = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix(self.identifierPrefix) }
                if !stale.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: stale)
                }
                for item in items {
                    self.schedule(todo: item)
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func identifier(for todo: Todo) -> String {
        identifierPrefix + todo.id.uuidString
    }

    private func finishAccess(_ granted: Bool, completion: ((Bool) -> Void)?) {
        DispatchQueue.main.async {
            completion?(granted)
        }
    }

    private static func leadText(_ minutes: Int) -> String {
        if minutes >= 1440, minutes % 1440 == 0 {
            return "\(minutes / 1440) 天"
        }
        if minutes >= 60, minutes % 60 == 0 {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }

    private static func bodyText(for todo: Todo, due: Date) -> String {
        var parts = ["截止 \(DateUtil.todoAbsoluteLabel(due))"]
        if !todo.people.isEmpty {
            parts.append(todo.people.map { "@\($0)" }.joined(separator: " "))
        }
        return parts.joined(separator: "  ·  ")
    }
}
