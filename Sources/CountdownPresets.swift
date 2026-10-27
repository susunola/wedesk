import Foundation

enum CountdownPresetRule {
    case solar(month: Int, day: Int)
    case lunar(month: Int, day: Int)
    case lunarNewYearsEve
    case qingming

    var cacheKey: String {
        switch self {
        case .solar(let month, let day):
            return "s\(month)-\(day)"
        case .lunar(let month, let day):
            return "l\(month)-\(day)"
        case .lunarNewYearsEve:
            return "eve"
        case .qingming:
            return "qingming"
        }
    }
}

struct CountdownPreset: Identifiable {
    let id: String
    let title: String
    let rule: CountdownPresetRule

    init(_ id: String, _ title: String, _ rule: CountdownPresetRule) {
        self.id = id
        self.title = title
        self.rule = rule
    }
}

enum CountdownPresets {
    static let popular: [CountdownPreset] = [
        CountdownPreset("newYear", "元旦", .solar(month: 1, day: 1)),
        CountdownPreset("springFestival", "春节", .lunar(month: 1, day: 1)),
        CountdownPreset("valentine", "情人节", .solar(month: 2, day: 14)),
        CountdownPreset("christmas", "圣诞节", .solar(month: 12, day: 25))
    ]

    static let more: [CountdownPreset] = [
        CountdownPreset("eve", "除夕", .lunarNewYearsEve),
        CountdownPreset("qingming", "清明节", .qingming),
        CountdownPreset("laborDay", "劳动节", .solar(month: 5, day: 1)),
        CountdownPreset("dragonBoat", "端午节", .lunar(month: 5, day: 5)),
        CountdownPreset("gaokao", "高考", .solar(month: 6, day: 7)),
        CountdownPreset("qixi", "七夕", .lunar(month: 7, day: 7)),
        CountdownPreset("midAutumn", "中秋节", .lunar(month: 8, day: 15)),
        CountdownPreset("teacher", "教师节", .solar(month: 9, day: 10)),
        CountdownPreset("nationalDay", "国庆节", .solar(month: 10, day: 1)),
        CountdownPreset("newYearsEve", "跨年", .solar(month: 12, day: 31))
    ]

    static func nextDate(for rule: CountdownPresetRule, from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        cacheResults(for: today)

        let key = rule.cacheKey
        if let cached = cache[key] {
            return cached
        }

        // 农历节日在公历上每年漂移，逐日扫描比推算农历边界更可靠。
        var result = today
        for offset in 1...420 {
            if let candidate = calendar.date(byAdding: .day, value: offset, to: today),
               matches(rule, on: candidate) {
                result = candidate
                break
            }
        }
        cache[key] = result
        return result
    }

    private static var cache: [String: Date] = [:]
    private static var cacheDay: Date?

    private static func cacheResults(for today: Date) {
        if cacheDay != today {
            cache.removeAll()
            cacheDay = today
        }
    }

    private static func matches(_ rule: CountdownPresetRule, on date: Date) -> Bool {
        switch rule {
        case .solar(let month, let day):
            let components = Calendar.current.dateComponents([.month, .day], from: date)
            return components.month == month && components.day == day
        case .lunar(let month, let day):
            return ChineseCalendarInfo.isLunarDate(date, month: month, day: day)
        case .lunarNewYearsEve:
            return ChineseCalendarInfo.isLunarNewYearsEve(date)
        case .qingming:
            return ChineseCalendarInfo.isQingming(date)
        }
    }
}
