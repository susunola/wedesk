import AppKit
import SwiftUI

struct PomodoroWidgetRoot: View {
    @EnvironmentObject private var store: TodoStore
    let onHide: () -> Void

    var body: some View {
        StandaloneWidgetCard(kind: .pomodoro, onHide: onHide) {
            PomodoroPanel(
                todos: store.items.filter { !$0.done },
                accent: store.accent,
                breakColor: Palette.accent(at: 2).color
            )
        }
    }
}

struct PomodoroPanel: View {
    @EnvironmentObject private var engine: PomodoroEngine
    let todos: [Todo]
    let accent: Color
    let breakColor: Color

    @State private var showSettings = false

    private var linkedTask: Todo? {
        guard let id = engine.taskID else { return nil }
        return todos.first { $0.id == id }
    }

    private var ringColor: Color {
        engine.isFocus ? accent : breakColor
    }

    private var caption: String {
        if let task = linkedTask {
            return engine.running ? task.title : "已关联 · \(task.title)"
        }
        if engine.running {
            return engine.isFocus ? "保持专注" : "放松一下"
        }
        return engine.remaining < engine.totalSeconds ? "已暂停" : "点击开始"
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                phasePill
                Spacer(minLength: 4)
                Text("今日 \(engine.stats.sessions) 段 · \(engine.stats.minutes) 分钟")
                    .font(.app(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            ring
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                taskMenu
                Spacer(minLength: 8)
                settingsButton
            }

            controls
        }
        .padding(.horizontal, 16)
        .padding(.top, 3)
        .padding(.bottom, 14)
    }

    private var phasePill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ringColor)
                .frame(width: 5, height: 5)

            Text(engine.phase.title)
                .font(.app(size: 10, weight: .medium))
                .foregroundStyle(ringColor)

            if engine.isFocus {
                Text("\(engine.nextPhaseNumber)/\(engine.settings.longEvery)")
                    .font(.app(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(ringColor.opacity(0.10)))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 8)

            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(engine.timeText)
                    .font(.app(size: 30, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.86))

                Text(caption)
                    .font(.app(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: 132, height: 132)
    }

    private var taskMenu: some View {
        Menu {
            Button("不关联任务") { engine.selectTask(nil) }

            if !todos.isEmpty {
                Divider()
                ForEach(todos) { todo in
                    Button(todo.title) { engine.selectTask(todo.id) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: linkedTask == nil ? "circle.dashed" : "target")
                    .font(.app(size: 9.5, weight: .medium))

                Text(linkedTask?.title ?? "关联待办任务")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.app(size: 10, weight: .medium))
            .foregroundStyle(linkedTask == nil ? Color.secondary : accent)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill((linkedTask == nil ? Color.primary : accent).opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(height: 28)
    }

    private var settingsButton: some View {
        Button {
            showSettings.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.app(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("计时设置")
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            PomodoroSettingsPanel(accent: accent)
                .frame(width: 260)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            roundButton("arrow.counterclockwise", help: "重置本段") {
                engine.reset()
            }

            Button(action: { engine.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: engine.running ? "pause.fill" : "play.fill")
                        .font(.app(size: 9.5, weight: .bold))

                    Text(primaryTitle)
                        .font(.app(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(ringColor))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            roundButton("forward.end.fill", help: "跳过本段") {
                engine.skip()
            }
        }
    }

    private var primaryTitle: String {
        if engine.running {
            return "暂停"
        }
        return engine.remaining < engine.totalSeconds ? "继续" : "开始"
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct PomodoroSettingsPanel: View {
    @EnvironmentObject private var engine: PomodoroEngine
    let accent: Color

    private let presets: [(name: String, focus: Int, rest: Int)] = [
        ("25 / 5", 25, 5),
        ("30 / 6", 30, 6),
        ("45 / 9", 45, 9),
        ("50 / 10", 50, 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("番茄钟设置")
                .font(.app(size: 12.5, weight: .semibold))

            HStack(spacing: 5) {
                ForEach(presets, id: \.name) { preset in
                    presetChip(preset.name, focus: preset.focus, rest: preset.rest)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)

            numberRow("专注", value: engine.settings.focusMinutes, in: 1...120) { minutes in
                engine.updateSettings { $0.focusMinutes = minutes }
            }
            .padding(.top, 2)

            numberRow("短休息", value: engine.settings.restMinutes, in: 1...60) { minutes in
                engine.updateSettings { $0.restMinutes = minutes }
            }

            numberRow("长休息", value: engine.settings.longRestMinutes, in: 1...90) { minutes in
                engine.updateSettings { $0.longRestMinutes = minutes }
            }

            numberRow("长休间隔", value: engine.settings.longEvery, in: 2...8, suffix: "段") { count in
                engine.updateSettings { $0.longEvery = count }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)

            Toggle("自动开始下一段", isOn: Binding(
                get: { engine.settings.autoStartNext },
                set: { value in engine.updateSettings { $0.autoStartNext = value } }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.app(size: 11.5))

            Toggle("结束提示音", isOn: Binding(
                get: { engine.settings.chime },
                set: { value in engine.updateSettings { $0.chime = value } }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.app(size: 11.5))

            HStack(spacing: 6) {
                Text("今日完成")
                    .font(.app(size: 11.5))

                Spacer()

                Text("\(engine.stats.sessions) 段 · \(engine.stats.minutes) 分钟")
                    .font(.app(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(accent)

                Button("清零") { engine.resetStats() }
                    .buttonStyle(.plain)
                    .font(.app(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func presetChip(_ name: String, focus: Int, rest: Int) -> some View {
        let active = engine.settings.focusMinutes == focus && engine.settings.restMinutes == rest

        return Button {
            engine.updateSettings {
                $0.focusMinutes = focus
                $0.restMinutes = rest
            }
        } label: {
            Text(name)
                .font(.app(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(active ? accent : Color.primary.opacity(0.05))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("专注 \(focus) 分钟 · 休息 \(rest) 分钟")
    }

    private func numberRow(
        _ label: String,
        value: Int,
        in range: ClosedRange<Int>,
        suffix: String = "分钟",
        set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.app(size: 11.5))

            Spacer(minLength: 4)

            Text("\(value) \(suffix)")
                .font(.app(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(accent)

            Stepper("", value: Binding(get: { value }, set: set), in: range)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}
