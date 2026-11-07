import AppKit
import SwiftUI

struct WidgetLibraryView: View {
    @ObservedObject var manager: WidgetManager
    @EnvironmentObject private var store: TodoStore
    @Environment(\.colorScheme) private var colorScheme
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            rows
            divider
            appearanceSection
            divider
            hotKeySection
            divider
            footer
        }
        .frame(width: 322)
        .background(
            WindowDragRegion()
                .background(colorScheme == .light ? Color.white : Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .light ? 0.09 : 0.16), lineWidth: 0.5)
        )
        .onExitCommand(perform: onClose)
    }

    private var appearanceSection: some View {
        let glass = store.cardMaterial.isGlass

        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.app(size: 11, weight: .medium))
                    .foregroundStyle(glass ? store.accent : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(glass ? store.accent.opacity(0.13) : Color.primary.opacity(0.055))
                    )

                VStack(alignment: .leading, spacing: 1.5) {
                    Text("卡片材质")
                        .font(.app(size: 12, weight: .medium))
                    Text(glass ? "桌布透进来，文字依旧清晰" : "不透明的纯白卡片")
                        .font(.app(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 4) {
                ForEach(CardMaterial.allCases) { material in
                    MaterialChip(
                        material: material,
                        selected: store.cardMaterial == material,
                        accent: store.accent
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            store.setCardMaterial(material)
                        }
                    }
                }
            }

            if glass {
                HStack(spacing: 8) {
                    Text("乳白")
                        .font(.app(size: 9.5))
                        .foregroundStyle(.tertiary)

                    Slider(
                        value: Binding(
                            get: { store.glassClarity },
                            set: { store.setGlassClarity($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    .tint(store.accent)
                    .help("白纱浓度：越往右越通透")

                    Text("通透")
                        .font(.app(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
    }

    private var hotKeySection: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.app(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                    )

                VStack(alignment: .leading, spacing: 1.5) {
                    Text("唤起 / 隐藏快捷键")
                        .font(.app(size: 12, weight: .medium))
                    Text("随时唤起或收起")
                        .font(.app(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HotkeyRecorder(display: hotKeyDisplay(store.hotKey)) { setting in
                    store.applyHotKey(setting, conflict: false)
                }

                Button(action: { store.resetHotKey() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.app(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("恢复默认 ⌃⌥T")
            }

            if store.hotKeyConflict {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.app(size: 8.5))
                        .foregroundStyle(.orange)
                    Text("该快捷键已被其他应用占用，请换一个")
                        .font(.app(size: 9.5))
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(store.accent.opacity(0.12))
                    .frame(width: 31, height: 31)

                Image(systemName: "square.grid.2x2")
                    .font(.app(size: 13, weight: .semibold))
                    .foregroundStyle(store.accent)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text("小组件")
                    .font(.app(size: 13.5, weight: .semibold))

                Text("挑一个放到桌面，随时可见")
                    .font(.app(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.app(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var rows: some View {
        VStack(spacing: 1) {
            ForEach(WidgetKind.allCases) { kind in
                WidgetLibraryRow(
                    kind: kind,
                    enabled: manager.isEnabled(kind),
                    accent: store.accent,
                    onToggle: {
                        manager.setEnabled(kind, enabled: !manager.isEnabled(kind))
                    }
                )
            }
        }
        .padding(7)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                Circle()
                    .fill(manager.deskVisible && !manager.enabledKinds.isEmpty
                          ? store.accent.opacity(0.85)
                          : Color.secondary.opacity(0.35))
                    .frame(width: 5, height: 5)

                Text(deskStatus)
                    .font(.app(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            footerButton(
                manager.deskVisible ? "全部收起" : "全部显示",
                symbol: manager.deskVisible ? "eye.slash" : "eye"
            ) {
                if manager.deskVisible {
                    manager.hideAll()
                } else {
                    manager.showAll()
                }
                onClose()
            }
            .disabled(manager.enabledKinds.isEmpty)

            footerButton("重置排列", symbol: "square.grid.2x2") {
                manager.resetPositions()
            }
            .disabled(manager.enabledKinds.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var deskStatus: String {
        if manager.enabledKinds.isEmpty {
            return "还没有组件"
        }
        if !manager.deskVisible {
            return "桌面已收起"
        }
        return "\(manager.enabledKinds.count) 个组件显示中"
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.app(size: 9, weight: .medium))
                Text(title)
                    .font(.app(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }
}

private struct MaterialChip: View {
    let material: CardMaterial
    let selected: Bool
    let accent: Color
    let onPick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            Text(material.title)
                .font(.app(size: 9.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.70))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? accent : Color.primary.opacity(hovering ? 0.075 : 0.04))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(material.help)
        .onHover { hovering = $0 }
    }
}

private struct WidgetLibraryRow: View {
    let kind: WidgetKind
    let enabled: Bool
    let accent: Color
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(enabled ? accent.opacity(0.13) : Color.primary.opacity(0.055))
                    .frame(width: 30, height: 30)

                Image(systemName: kind.symbol)
                    .font(.app(size: 12.5, weight: .medium))
                    .foregroundStyle(enabled ? accent : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(kind.title)
                    .font(.app(size: 12, weight: .medium))
                    .foregroundStyle(enabled ? Color.primary : Color.secondary)

                Text(kind.subtitle)
                    .font(.app(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onToggle) {
                HStack(spacing: 3) {
                    if enabled {
                        Image(systemName: "checkmark")
                            .font(.app(size: 7.5, weight: .bold))
                    }

                    Text(enabled ? "已添加" : "添加")
                        .font(.app(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(enabled ? accent : (hovering ? accent : Color.secondary))
                .frame(width: 52, height: 21)
                .background(
                    Capsule()
                        .fill(enabled
                              ? accent.opacity(0.12)
                              : Color.primary.opacity(hovering ? 0.085 : 0.045))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(enabled ? "从桌面移除\(kind.title)组件" : "把\(kind.title)放到桌面")
        }
        .padding(.horizontal, 9)
        .frame(height: 47)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.038 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
