import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeySetting: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeySetting(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey))
}

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .action()
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x44544F44), id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, ref != nil else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
            return nil
        }
        hotKeyRef = ref
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

// MARK: - Display

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    if flags.contains(.option) { carbon |= UInt32(optionKey) }
    if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    return carbon
}

func hotKeyDisplay(_ setting: HotKeySetting) -> String {
    var s = ""
    if setting.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
    if setting.modifiers & UInt32(optionKey) != 0 { s += "⌥" }
    if setting.modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
    if setting.modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
    s += keyCodeDisplay(setting.keyCode)
    return s
}

private func keyCodeDisplay(_ keyCode: UInt32) -> String {
    switch keyCode {
    case UInt32(kVK_Return): return "↩"
    case UInt32(kVK_Tab): return "⇥"
    case UInt32(kVK_Space): return "Space"
    case UInt32(kVK_Delete): return "⌫"
    case UInt32(kVK_Escape): return "⎋"
    case UInt32(kVK_F1): return "F1"
    case UInt32(kVK_F2): return "F2"
    case UInt32(kVK_F3): return "F3"
    case UInt32(kVK_F4): return "F4"
    case UInt32(kVK_F5): return "F5"
    case UInt32(kVK_F6): return "F6"
    case UInt32(kVK_F7): return "F7"
    case UInt32(kVK_F8): return "F8"
    case UInt32(kVK_F9): return "F9"
    case UInt32(kVK_F10): return "F10"
    case UInt32(kVK_F11): return "F11"
    case UInt32(kVK_F12): return "F12"
    case UInt32(kVK_LeftArrow): return "←"
    case UInt32(kVK_RightArrow): return "→"
    case UInt32(kVK_UpArrow): return "↑"
    case UInt32(kVK_DownArrow): return "↓"
    case UInt32(kVK_Home): return "↖"
    case UInt32(kVK_End): return "↘"
    case UInt32(kVK_PageUp): return "⇞"
    case UInt32(kVK_PageDown): return "⇟"
    default:
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = unsafeBitCast(layoutData, to: CFData.self)
        let layoutPtr = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        UCKeyTranslate(
            layoutPtr,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
        guard length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

// MARK: - Recorder

struct HotkeyRecorder: NSViewRepresentable {
    let display: String
    let onCapture: (HotKeySetting) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        nsView.displayText = display
    }

    final class Coordinator {
        let onCapture: (HotKeySetting) -> Void
        weak var view: HotkeyRecorderView?

        init(onCapture: @escaping (HotKeySetting) -> Void) {
            self.onCapture = onCapture
        }
    }
}

final class HotkeyRecorderView: NSView {
    weak var coordinator: HotkeyRecorder.Coordinator?
    var displayText = "" {
        didSet { needsDisplay = true }
    }
    private(set) var isRecording = false
    private var wantsRecording = false
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { wantsRecording }

    override func becomeFirstResponder() -> Bool {
        guard wantsRecording, super.becomeFirstResponder() else { return false }
        isRecording = true
        needsDisplay = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.endRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil }
            let setting = HotKeySetting(
                keyCode: UInt32(event.keyCode),
                modifiers: carbonModifiers(from: mods)
            )
            self.endRecording()
            self.coordinator?.onCapture(setting)
            return nil
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return true
    }

    private func endRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        wantsRecording = false
        if isRecording {
            isRecording = false
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        wantsRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 86, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11)
        if isRecording {
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            NSColor.systemBlue.setStroke()
        } else {
            NSColor.black.withAlphaComponent(0.045).setFill()
            NSColor.black.withAlphaComponent(0.10).setStroke()
        }
        path.fill()
        path.lineWidth = 0.5
        path.stroke()

        let text = isRecording ? "按下快捷键…" : displayText
        let color = isRecording ? NSColor.systemBlue : NSColor.black.withAlphaComponent(0.65)
        let font = isRecording
            ? (NSFont(name: wenkaiMedium, size: 10.5) ?? NSFont.systemFont(ofSize: 10.5))
            : NSFont.systemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
