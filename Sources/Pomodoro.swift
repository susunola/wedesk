import AppKit
import Foundation
import SwiftUI

final class PomodoroEngine: ObservableObject {
    enum Phase: String, Codable {
        case focus
        case rest
        case longRest

        var title: String {
            switch self {
            case .focus: return "专注"
            case .rest: return "短休"
            case .longRest: return "长休"
            }
        }
    }

    struct Settings: Codable, Equatable {
        var focusMinutes = 25
        var restMinutes = 5
        var longRestMinutes = 15
        var longEvery = 4
        var autoStartNext = true
        var chime = true
    }

    struct DayStats: Codable, Equatable {
        var day = ""
        var sessions = 0
        var minutes = 0
    }

    @Published private(set) var settings: Settings
    @Published private(set) var phase: Phase
    @Published private(set) var running: Bool
    @Published private(set) var remaining: Int
    @Published private(set) var cyclesDone: Int
    @Published private(set) var stats: DayStats
    @Published private(set) var taskID: UUID?

    private var endAt: Date?
    private var timer: Timer?

    private let settingsKey = "wedesk.pomodoro.settings.v1"
    private let statsKey = "wedesk.pomodoro.stats.v1"
    private let runKey = "wedesk.pomodoro.run.v1"

    private struct RunState: Codable {
        var phase: Phase
        var remaining: Int
        var endAt: Date?
        var cyclesDone: Int
        var taskID: UUID?
    }

    init() {
        var loadedSettings = Settings()
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            loadedSettings = decoded
        }
        settings = loadedSettings

        var loadedStats = DayStats(day: Self.todayKey())
        if let data = UserDefaults.standard.data(forKey: statsKey),
           let decoded = try? JSONDecoder().decode(DayStats.self, from: data),
           decoded.day == Self.todayKey() {
            loadedStats = decoded
        }
        stats = loadedStats

        phase = .focus
        remaining = loadedSettings.focusMinutes * 60
        cyclesDone = 0
        running = false
        taskID = nil
        endAt = nil
        timer = nil

        if let data = UserDefaults.standard.data(forKey: runKey),
           let decoded = try? JSONDecoder().decode(RunState.self, from: data) {
            phase = decoded.phase
            cyclesDone = decoded.cyclesDone
            taskID = decoded.taskID
            if let end = decoded.endAt, end > Date() {
                remaining = max(1, Int(end.timeIntervalSinceNow.rounded(.up)))
                running = true
                endAt = end
            } else if decoded.endAt == nil {
                remaining = max(1, decoded.remaining)
            } else {
                remaining = decoded.phase.duration(using: loadedSettings)
            }
        }

        if running {
            startTimer()
        }
    }

    // MARK: - Derived

    var totalSeconds: Int {
        phase.duration(using: settings)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(Double(remaining) / Double(totalSeconds), 0), 1)
    }

    var timeText: String {
        String(format: "%d:%02d", max(0, remaining) / 60, max(0, remaining) % 60)
    }

    var isFocus: Bool {
        phase == .focus
    }

    var nextPhaseNumber: Int {
        min(cyclesDone + 1, max(settings.longEvery, 1))
    }

    // MARK: - Controls

    func toggle() {
        if running {
            pause()
        } else {
            start()
        }
    }

    func start() {
        refreshStatsDay()
        if remaining <= 0 {
            remaining = totalSeconds
        }
        endAt = Date().addingTimeInterval(TimeInterval(remaining))
        running = true
        startTimer()
        persistRun()
    }

    func pause() {
        guard running else { return }
        remaining = max(1, computedRemaining())
        running = false
        endAt = nil
        stopTimer()
        persistRun()
    }

    func reset() {
        stopTimer()
        running = false
        endAt = nil
        remaining = totalSeconds
        persistRun()
    }

    func skip() {
        advance(countsSession: false)
    }

    func selectTask(_ id: UUID?) {
        guard id != taskID else { return }
        taskID = id
        persistRun()
    }

    // MARK: - Settings

    func updateSettings(_ mutate: (inout Settings) -> Void) {
        var next = settings
        mutate(&next)
        next.focusMinutes = min(max(next.focusMinutes, 1), 120)
        next.restMinutes = min(max(next.restMinutes, 1), 60)
        next.longRestMinutes = min(max(next.longRestMinutes, 1), 90)
        next.longEvery = min(max(next.longEvery, 2), 8)
        settings = next

        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }

        if !running {
            remaining = totalSeconds
            persistRun()
        }
    }

    func resetStats() {
        stats = DayStats(day: Self.todayKey())
        persistStats()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        refreshStatsDay()
        let value = computedRemaining()
        if value <= 0 {
            advance(countsSession: phase == .focus)
        } else if value != remaining {
            remaining = value
        }
    }

    private func computedRemaining() -> Int {
        guard let endAt else { return remaining }
        return max(0, Int(endAt.timeIntervalSinceNow.rounded(.up)))
    }

    private func advance(countsSession: Bool) {
        stopTimer()
        running = false
        endAt = nil

        if countsSession, phase == .focus {
            cyclesDone += 1
            stats.sessions += 1
            stats.minutes += settings.focusMinutes
            persistStats()
        }

        let finished = phase
        switch finished {
        case .focus:
            phase = cyclesDone >= settings.longEvery ? .longRest : .rest
        case .rest, .longRest:
            if finished == .longRest {
                cyclesDone = 0
            }
            phase = .focus
        }

        remaining = totalSeconds
        announce(from: finished)

        if settings.autoStartNext {
            start()
        } else {
            persistRun()
        }
    }

    private func announce(from finished: Phase) {
        if settings.chime {
            NSSound(named: "Glass")?.play()
        }

        switch finished {
        case .focus:
            ReminderCenter.shared.notifyPomodoro(
                title: "专注完成",
                body: "休息 \(phase == .longRest ? settings.longRestMinutes : settings.restMinutes) 分钟"
            )
        case .rest, .longRest:
            ReminderCenter.shared.notifyPomodoro(
                title: "休息结束",
                body: "开始下一个 \(settings.focusMinutes) 分钟专注"
            )
        }
    }

    private func refreshStatsDay() {
        let key = Self.todayKey()
        guard stats.day != key else { return }
        stats = DayStats(day: key, sessions: 0, minutes: 0)
        cyclesDone = 0
        persistStats()
    }

    private func persistStats() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: statsKey)
    }

    private func persistRun() {
        let state = RunState(
            phase: phase,
            remaining: remaining,
            endAt: endAt,
            cyclesDone: cyclesDone,
            taskID: taskID
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: runKey)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func todayKey() -> String {
        dayFormatter.string(from: Date())
    }
}

private extension PomodoroEngine.Phase {
    func duration(using settings: PomodoroEngine.Settings) -> Int {
        switch self {
        case .focus: return settings.focusMinutes * 60
        case .rest: return settings.restMinutes * 60
        case .longRest: return settings.longRestMinutes * 60
        }
    }
}
