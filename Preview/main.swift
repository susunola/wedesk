import AppKit
import SwiftUI

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    private var previewWidth: CGFloat = 320

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.removeObject(forKey: "desktodo.items.v1")
        UserDefaults.standard.removeObject(forKey: "desktodo.avatar.on.v1")
        UserDefaults.standard.removeObject(forKey: "desktodo.countdowns.v1")
        let store = TodoStore()
        if ProcessInfo.processInfo.environment["PREVIEW_EMPTY"] == nil {
            let now = Date()
            store.add(
                "跟 @王晴 确认售后支持范围",
                dueAt: now.addingTimeInterval(45 * 60),
                reminderLead: 0
            )
            store.add(
                "整理售后支持汇报材料",
                dueAt: DateUtil.todoTomorrowMorning(),
                reminderLead: 10,
                mentions: ["王晴", "李总"]
            )
            store.add(
                "回复客户邮件",
                dueAt: now.addingTimeInterval(3 * 24 * 3600),
                mentions: ["客户A"]
            )
            store.add(
                "提交上周成本优化建议",
                dueAt: now.addingTimeInterval(-2 * 24 * 3600),
                reminderLead: 0
            )
            store.add("和设计对一下新版落地方案")
            if let index = store.items.firstIndex(where: { $0.title == "提交上周成本优化建议" }) {
                store.toggle(store.items[index])
            }
        }
        if ProcessInfo.processInfo.environment["PREVIEW_NO_COUNTDOWN"] == nil {
            let calendar = Calendar.current
            store.addCountdown("GM 汇报", on: calendar.date(byAdding: .day, value: 12, to: Date()) ?? Date())
            store.addCountdown("合同续签", on: calendar.date(byAdding: .day, value: 45, to: Date()) ?? Date())
            store.addCountdown("项目启动", on: calendar.date(byAdding: .day, value: -8, to: Date()) ?? Date())
        }
        if let raw = ProcessInfo.processInfo.environment["PREVIEW_ACCENT"], let index = Int(raw) {
            store.setAccent(index)
        }
        if ProcessInfo.processInfo.environment["PREVIEW_NO_AVATAR"] != nil {
            store.setShowAvatar(false)
        }

        let environment = ProcessInfo.processInfo.environment
        let root: AnyView
        if environment["PREVIEW_EDITOR"] != nil {
            previewWidth = 292 + 36
            var sample = Todo(title: "整理售后支持汇报材料")
            sample.dueAt = DateUtil.todoTomorrowMorning()
            sample.reminderLead = 10
            sample.mentions = ["王晴", "李总"]
            root = AnyView(
                TodoEditorPopover(
                    item: sample,
                    accent: store.accent,
                    onSave: { _, _, _, _ in },
                    onCancel: {}
                )
                .padding(18)
                .background(Color(nsColor: .windowBackgroundColor))
            )
        } else if environment["PREVIEW_SCHEDULE"] != nil {
            previewWidth = 268 + 36
            root = AnyView(
                SchedulePopover(
                    date: .constant(DateUtil.todoOneHourLater()),
                    reminderLead: .constant(10),
                    accent: store.accent,
                    onClear: {},
                    onDone: {}
                )
                .padding(18)
                .background(Color(nsColor: .windowBackgroundColor))
            )
        } else if environment["PREVIEW_LIBRARY"] != nil {
            previewWidth = 322 + 36
            let manager = WidgetManager(store: store)
            root = AnyView(
                WidgetLibraryView(manager: manager, onClose: {})
                    .environmentObject(store)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(18)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        } else if environment["PREVIEW_CALENDAR"] != nil {
            let picking = environment["PREVIEW_PICK"] != nil
            let sample = Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date()
            let previewMonth = environment["PREVIEW_CALENDAR_MONTH"].flatMap { raw -> Date? in
                let parts = raw.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            }
            root = AnyView(
                CalendarPopover(
                    accent: store.accent,
                    countdownDays: picking ? [] : Set(store.countdowns.map {
                        Calendar.current.startOfDay(for: $0.date)
                    }),
                    selection: picking ? Binding.constant(sample) : nil,
                    initialMonth: previewMonth
                )
                .padding(18)
                .background(Color(nsColor: .windowBackgroundColor))
            )
        } else if environment["PREVIEW_COUNTDOWN"] != nil {
            root = AnyView(
                CountdownPopover(accent: store.accent)
                    .environmentObject(store)
                    .padding(18)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
        } else {
            root = AnyView(ContentView().environmentObject(store))
        }

        let size = NSSize(width: previewWidth, height: 440)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["PREVIEW_DARK"] != nil ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: root)
        window.setFrameOrigin(NSPoint(x: 240, y: 240))
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.capture()
        }
    }

    private func capture() {
        defer { NSApp.terminate(nil) }
        guard let view = window.contentView, let layer = view.layer else {
            print("no layer")
            return
        }

        view.layoutSubtreeIfNeeded()
        let fitted = view.fittingSize
        let size = NSSize(width: previewWidth, height: max(180, fitted.height))
        window.setContentSize(size)
        view.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("no ctx")
            return
        }

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        let dark = ProcessInfo.processInfo.environment["PREVIEW_DARK"] != nil
        ctx.setFillColor((dark
            ? NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)
            : NSColor(calibratedRed: 0.84, green: 0.85, blue: 0.87, alpha: 1)).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        layer.render(in: ctx)

        guard let image = ctx.makeImage() else {
            print("no image")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/preview_todo.png"))
        print("captured /tmp/preview_todo.png")
    }
}

let app = NSApplication.shared
let delegate = PreviewDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
