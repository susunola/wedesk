import AppKit
import SwiftUI

final class WidgetWindow: NSWindow {
    var kind: WidgetKind?
    var onFrameSettled: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func notifyDragEnded() {
        onFrameSettled?()
    }

    func applyPin(_ pinned: Bool) {
        if pinned {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone, .ignoresCycle]
        } else {
            level = .normal
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragRegionView {
        let view = WindowDragRegionView(frame: .zero)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: WindowDragRegionView, context: Context) {}
}

final class WindowDragRegionView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }
        let before = window.frame
        window.performDrag(with: event)
        if window.frame != before {
            (window as? WidgetWindow)?.notifyDragEnded()
        }
    }
}

struct WindowResizeRegion: NSViewRepresentable {
    var minSize: CGSize
    var maxSize: CGSize

    func makeNSView(context: Context) -> WindowResizeRegionView {
        let view = WindowResizeRegionView(frame: .zero)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: WindowResizeRegionView, context: Context) {
        nsView.minSize = minSize
        nsView.maxSize = maxSize
    }
}

/// 右下角拖拽改尺寸：左上角保持不动，宽高分别夹在组件允许范围内且不超出屏幕。
enum WidgetResize {
    static func frame(
        start: NSRect,
        drag: CGSize,
        limit: NSRect?,
        minSize: CGSize,
        maxSize: CGSize
    ) -> NSRect {
        let topEdge = start.maxY
        var width = start.width + drag.width
        var height = start.height - drag.height

        width = min(max(width, minSize.width), maxSize.width)
        height = min(max(height, minSize.height), maxSize.height)
        if let limit {
            width = min(width, max(limit.maxX - start.minX, minSize.width))
            height = min(height, max(topEdge - limit.minY, minSize.height))
        }

        var frame = start
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = topEdge - height
        return frame
    }
}

final class WindowResizeRegionView: NSView {
    var minSize = CGSize(width: 260, height: 240)
    var maxSize = CGSize(width: 560, height: 820)

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.cornerCursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }

        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        let limit = (window.screen ?? NSScreen.main)?.visibleFrame

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }

            let mouse = NSEvent.mouseLocation
            window.setFrame(
                WidgetResize.frame(
                    start: startFrame,
                    drag: CGSize(width: mouse.x - startMouse.x, height: mouse.y - startMouse.y),
                    limit: limit,
                    minSize: minSize,
                    maxSize: maxSize
                ),
                display: true
            )
        }

        (window as? WidgetWindow)?.notifyDragEnded()
    }

    private static let cornerCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 5, y: 17))
        path.line(to: NSPoint(x: 17, y: 5))
        path.move(to: NSPoint(x: 5, y: 17))
        path.line(to: NSPoint(x: 5, y: 12))
        path.move(to: NSPoint(x: 5, y: 17))
        path.line(to: NSPoint(x: 10, y: 17))
        path.move(to: NSPoint(x: 17, y: 5))
        path.line(to: NSPoint(x: 17, y: 10))
        path.move(to: NSPoint(x: 17, y: 5))
        path.line(to: NSPoint(x: 12, y: 5))
        path.lineCapStyle = .round
        path.lineWidth = 3.4
        NSColor.white.setStroke()
        path.stroke()
        path.lineWidth = 1.5
        NSColor.black.setStroke()
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 11, y: 11))
    }()
}

struct WidgetResizeHandle: View {
    let kind: WidgetKind
    let visible: Bool

    var body: some View {
        WindowResizeRegion(
            minSize: kind.windowSize(for: kind.minSize),
            maxSize: kind.windowSize(for: kind.maxSize)
        )
        .frame(width: 15, height: 15)
            .overlay(alignment: .bottomTrailing) {
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 2.5))
                    path.addLine(to: CGPoint(x: 2.5, y: 10))
                    path.move(to: CGPoint(x: 10, y: 6.5))
                    path.addLine(to: CGPoint(x: 6.5, y: 10))
                }
                .stroke(
                    Color.primary.opacity(0.30),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .frame(width: 12, height: 12)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
            }
            .padding(7)
            .animation(.easeOut(duration: 0.15), value: visible)
            .help("拖动调整大小")
    }
}
