import AppKit
import Carbon.HIToolbox
import Combine
import CoreText
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = TodoStore()
    private lazy var manager = WidgetManager(store: store)
    private var libraryWindow: NSWindow?
    private var globalHotKey: GlobalHotKey?
    private var cancellable: AnyCancellable?
    private var pomodoroCancellable: AnyCancellable?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundledFonts()
        installMainMenu()
        setupStatusItem()
        ReminderCenter.shared.configure()

        manager.onOpenLibrary = { [weak self] in
            DispatchQueue.main.async { self?.presentLibrary() }
        }

        manager.start()
        store.syncReminders()

        // 开发自检用：WEDESK_DEBUG_YEAR=1 启动时直接弹出全年总览，方便截图核对排版。
        if ProcessInfo.processInfo.environment["WEDESK_DEBUG_YEAR"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.manager.toggleYearOverview()
            }
            // WEDESK_DEBUG_PICK=1 再模拟一次"点了某个月"，验证日历卡真的会跳过去。
            if ProcessInfo.processInfo.environment["WEDESK_DEBUG_PICK"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    let components = DateComponents(year: 2026, month: 4, day: 1)
                    self?.store.calendarFocusMonth = Calendar.current.date(from: components)
                }
            }
        }

        installHotKey()
        cancellable = store.$hotKey
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.installHotKey()
            }

        pomodoroCancellable = store.pomodoro.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusTitle()
            }
        refreshStatusTitle()

        if manager.enabledKinds.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.presentLibrary()
            }
        }
    }

    private func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts")
        else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private func installHotKey() {
        globalHotKey = nil
        let setting = store.hotKey
        globalHotKey = GlobalHotKey(keyCode: setting.keyCode, modifiers: setting.modifiers) { [weak self] in
            self?.manager.toggleAll()
        }
        if globalHotKey == nil {
            store.applyHotKey(setting, conflict: true)
        } else if store.hotKeyConflict {
            store.applyHotKey(setting, conflict: false)
        }
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarIcon()
        item.button?.toolTip = "WeDesk"

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func refreshStatusTitle() {
        let engine = store.pomodoro
        statusItem?.button?.title = engine.running ? "  \(engine.timeText)" : ""
    }

    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let text = NSAttributedString(string: "W", attributes: attrs)
        let textSize = text.size()
        text.draw(at: NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        ))
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "开机启动设置失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func aboutWeDesk(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func toggleWidgets(_ sender: Any?) {
        manager.toggleAll()
    }

    @objc private func togglePomodoro(_ sender: Any?) {
        store.pomodoro.toggle()
    }

    @objc private func skipPomodoro(_ sender: Any?) {
        store.pomodoro.skip()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleTitle = manager.deskVisible ? "收起所有小组件" : "显示所有小组件"
        menu.addItem(makeMenuItem(toggleTitle, #selector(toggleWidgets(_:))))
        menu.addItem(makeMenuItem("小组件库…", #selector(openLibraryFromMenu(_:))))
        menu.addItem(makeMenuItem("重置组件排列", #selector(resetPositions(_:))))
        menu.addItem(.separator())

        let engine = store.pomodoro
        menu.addItem(makeMenuItem(
            engine.running ? "暂停专注" : "开始专注",
            #selector(togglePomodoro(_:))
        ))
        menu.addItem(makeMenuItem("跳过当前阶段", #selector(skipPomodoro(_:))))

        let statsItem = NSMenuItem(
            title: "今日 \(engine.stats.sessions) 段 · \(engine.stats.minutes) 分钟",
            action: nil,
            keyEquivalent: ""
        )
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let login = makeMenuItem("开机自动启动", #selector(toggleLaunchAtLogin(_:)))
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        let hotKeyItem = NSMenuItem(
            title: "唤起快捷键 \(hotKeyDisplay(store.hotKey))",
            action: nil,
            keyEquivalent: ""
        )
        hotKeyItem.isEnabled = false
        menu.addItem(hotKeyItem)
        menu.addItem(.separator())

        menu.addItem(makeMenuItem("关于 WeDesk", #selector(aboutWeDesk(_:))))
        let quit = NSMenuItem(title: "退出 WeDesk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        toggleLibrary()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.persistAllFrames()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(makeMenuItem("小组件库…", #selector(openLibraryFromMenu(_:))))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem("显示所有小组件", #selector(showAllWidgets(_:))))
        menu.addItem(makeMenuItem("收起所有小组件", #selector(hideAllWidgets(_:))))
        menu.addItem(makeMenuItem("重置组件排列", #selector(resetPositions(_:))))
        menu.addItem(.separator())
        let login = makeMenuItem("开机自动启动", #selector(toggleLaunchAtLogin(_:)))
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)
        return menu
    }

    // MARK: - Main menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "WeDesk")
        let about = NSMenuItem(
            title: "关于 WeDesk",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        appMenu.addItem(makeMenuItem("小组件库…", #selector(openLibraryFromMenu(_:)), keyEquivalent: "l"))
        appMenu.addItem(makeMenuItem("显示所有小组件", #selector(showAllWidgets(_:))))
        appMenu.addItem(makeMenuItem("收起所有小组件", #selector(hideAllWidgets(_:)), keyEquivalent: "m"))
        appMenu.addItem(makeMenuItem("重置组件排列", #selector(resetPositions(_:))))
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 WeDesk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)

        let appItem = NSMenuItem(title: "WeDesk", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: Selector(("cut:")), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: Selector(("copy:")), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: Selector(("paste:")), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: Selector(("selectAll:")), keyEquivalent: "a"))

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func makeMenuItem(_ title: String, _ action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    // MARK: - Widget library

    private func presentLibrary() {
        NSApp.activate(ignoringOtherApps: true)

        if libraryWindow == nil {
            libraryWindow = makeLibraryWindow()
        }
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeLibraryWindow() -> NSWindow {
        let root = WidgetLibraryView(
            manager: manager,
            onClose: { [weak self] in
                self?.closeLibrary()
            }
        )
        .environmentObject(store)

        let hosting = LibraryHostingView(rootView: root)
        hosting.wantsLayer = true

        let window = LibraryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 322, height: 290),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .utilityWindow
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.title = "小组件库"
        window.contentView = hosting

        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        let height = fitted.height > 100 ? fitted.height : 290
        window.setContentSize(NSSize(width: 322, height: height))
        window.center()
        return window
    }

    private func toggleLibrary() {
        if let window = libraryWindow,
           window.isVisible,
           NSApp.isActive,
           window.isKeyWindow {
            closeLibrary()
        } else {
            presentLibrary()
        }
    }

    private func closeLibrary() {
        libraryWindow?.orderOut(nil)
        NSApp.deactivate()
    }

    // MARK: - Actions

    @objc private func showAllWidgets(_ sender: Any?) {
        manager.showAll()
    }

    @objc private func hideAllWidgets(_ sender: Any?) {
        closeLibrary()
        manager.hideAll()
    }

    @objc private func openLibraryFromMenu(_ sender: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.presentLibrary()
        }
    }

    @objc private func resetPositions(_ sender: Any?) {
        manager.resetPositions()
        if !manager.deskVisible {
            manager.showAll()
        }
    }
}

private final class LibraryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class LibraryHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
