import AppKit
import SwiftUI

struct StandaloneWidgetCard<Content: View>: View {
    let kind: WidgetKind
    let onHide: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: TodoStore
    @State private var hovering = false
    @State private var confirmHide = false
    @State private var confirmReset: DispatchWorkItem?

    var body: some View {
        GeometryReader { proxy in
            let card = kind.cardSize(for: proxy.size)

            VStack(spacing: 0) {
                chrome
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: card.width, height: card.height)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Color.cardBorder(material: store.cardMaterial, colorScheme: colorScheme),
                        lineWidth: 0.5
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                WidgetResizeHandle(kind: kind, visible: hovering)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.16 : 0.32),
                radius: 15,
                y: 6
            )
            .padding(WidgetKind.shadowPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { inside in
            hovering = inside
            if !inside {
                confirmReset?.cancel()
                confirmHide = false
            }
        }
        .accessibilityLabel("\(kind.title)小组件")
    }

    private var chrome: some View {
        ZStack {
            Capsule()
                .fill(Color.primary.opacity(hovering ? 0.22 : 0.14))
                .frame(width: 24, height: 3)

            HStack {
                Spacer()
                hideButton
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .contentShape(Rectangle())
        .background(WindowDragRegion())
        // 握把条整条都能拖（右侧留出关闭按钮的位置），不依赖 SwiftUI 对纯色图形的命中判定。
        .overlay(alignment: .leading) {
            WindowDragRegion()
                .frame(height: 22)
                .padding(.trailing, 46)
        }
        .help("拖动顶部可移动")
    }

    /// 误触过一次「移除」后需要再点一次确认，避免卡片被顺手清掉。
    private var hideButton: some View {
        Group {
            if confirmHide {
                Button(action: onHide) {
                    Text("确认移除")
                        .font(.app(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(nsColor: .systemRed)))
                        .contentShape(Capsule())
                }
            } else {
                Button(action: armHideConfirmation) {
                    Image(systemName: "xmark")
                        .font(.app(size: 7.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .contentShape(Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .help(confirmHide ? "再点一次才会从桌面移除" : "从桌面移除")
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
        .animation(.easeOut(duration: 0.12), value: confirmHide)
    }

    private func armHideConfirmation() {
        confirmHide = true
        confirmReset?.cancel()
        let reset = DispatchWorkItem { confirmHide = false }
        confirmReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: reset)
    }

    @ViewBuilder
    private var cardBackground: some View {
        CardBackground(material: store.cardMaterial, clarity: store.glassClarity)
    }
}

struct CountdownWidgetRoot: View {
    @EnvironmentObject private var store: TodoStore
    let onHide: () -> Void

    var body: some View {
        StandaloneWidgetCard(kind: .countdown, onHide: onHide) {
            CountdownPopover(accent: store.accent, fillHeight: true)
        }
    }
}

struct CalendarWidgetRoot: View {
    @EnvironmentObject private var store: TodoStore
    let onHide: () -> Void

    var body: some View {
        StandaloneWidgetCard(kind: .calendar, onHide: onHide) {
            CalendarPopover(
                accent: store.accent,
                countdownDays: store.upcomingCountdownDays,
                todoDays: store.pendingTodoDays,
                tasksProvider: { store.pendingTodos(on: $0) },
                onToggleTask: { store.toggle($0) },
                dayAnchor: store.dayAnchor
            )
        }
    }
}
