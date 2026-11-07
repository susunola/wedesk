import Foundation

enum ChineseCalendarInfo {
    struct Badge {
        enum Kind {
            case lunar
            case festival
            case rest
            case makeup
        }

        let text: String
        let kind: Kind
    }

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    private static let chinese: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    private static let lunarMonths = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    private static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    // 2025/2026 为国务院办公厅公布安排；2027 为待公布的预测版；更晚年份只按节日和农历显示。
    private static let schedule: [Int: Badge] = {
        var map: [Int: Badge] = [:]

        func add(_ year: Int, _ month: Int, _ day: Int, _ text: String, _ kind: Badge.Kind) {
            map[year * 10000 + month * 100 + day] = Badge(text: text, kind: kind)
        }

        func addRange(_ year: Int, _ month: Int, _ days: ClosedRange<Int>, _ text: String, _ kind: Badge.Kind) {
            for day in days {
                add(year, month, day, text, kind)
            }
        }

        // 2025
        add(2025, 1, 1, "元旦", .festival)
        add(2025, 1, 26, "班", .makeup)
        add(2025, 1, 28, "除夕", .festival)
        add(2025, 1, 29, "春节", .festival)
        addRange(2025, 1, 30...31, "休", .rest)
        addRange(2025, 2, 1...4, "休", .rest)
        add(2025, 2, 8, "班", .makeup)
        add(2025, 4, 4, "清明节", .festival)
        addRange(2025, 4, 5...6, "休", .rest)
        add(2025, 4, 27, "班", .makeup)
        add(2025, 5, 1, "劳动节", .festival)
        addRange(2025, 5, 2...5, "休", .rest)
        add(2025, 5, 31, "端午节", .festival)
        addRange(2025, 6, 1...2, "休", .rest)
        add(2025, 9, 28, "班", .makeup)
        add(2025, 10, 1, "国庆节", .festival)
        addRange(2025, 10, 2...5, "休", .rest)
        add(2025, 10, 6, "中秋节", .festival)
        addRange(2025, 10, 7...8, "休", .rest)
        add(2025, 10, 11, "班", .makeup)

        // 2026
        add(2026, 1, 1, "元旦", .festival)
        addRange(2026, 1, 2...3, "休", .rest)
        add(2026, 1, 4, "班", .makeup)
        add(2026, 2, 14, "班", .makeup)
        add(2026, 2, 15, "休", .rest)
        add(2026, 2, 16, "除夕", .festival)
        add(2026, 2, 17, "春节", .festival)
        addRange(2026, 2, 18...23, "休", .rest)
        add(2026, 2, 28, "班", .makeup)
        add(2026, 4, 4, "休", .rest)
        add(2026, 4, 5, "清明节", .festival)
        add(2026, 4, 6, "休", .rest)
        add(2026, 5, 1, "劳动节", .festival)
        addRange(2026, 5, 2...5, "休", .rest)
        add(2026, 5, 9, "班", .makeup)
        add(2026, 6, 19, "端午节", .festival)
        addRange(2026, 6, 20...21, "休", .rest)
        add(2026, 9, 20, "班", .makeup)
        add(2026, 9, 25, "中秋节", .festival)
        addRange(2026, 9, 26...27, "休", .rest)
        add(2026, 10, 1, "国庆节", .festival)
        addRange(2026, 10, 2...7, "休", .rest)
        add(2026, 10, 10, "班", .makeup)

        // 2027：官方通知尚未发布，按现行规则与公开预测版暂标，发布后校准。
        add(2027, 1, 1, "元旦", .festival)
        addRange(2027, 1, 2...3, "休", .rest)
        add(2027, 1, 31, "班", .makeup)
        add(2027, 2, 5, "除夕", .festival)
        add(2027, 2, 6, "春节", .festival)
        addRange(2027, 2, 7...13, "休", .rest)
        add(2027, 2, 14, "班", .makeup)
        addRange(2027, 4, 3...4, "休", .rest)
        add(2027, 4, 5, "清明节", .festival)
        add(2027, 5, 1, "劳动节", .festival)
        addRange(2027, 5, 2...5, "休", .rest)
        add(2027, 5, 8, "班", .makeup)
        add(2027, 6, 9, "端午节", .festival)
        add(2027, 9, 15, "中秋节", .festival)
        add(2027, 9, 26, "班", .makeup)
        add(2027, 10, 1, "国庆节", .festival)
        addRange(2027, 10, 2...7, "休", .rest)
        add(2027, 10, 9, "班", .makeup)

        return map
    }()

    private static let qingmingDays: [Int: Int] = [
        2024: 4, 2025: 4, 2026: 5, 2027: 5, 2028: 4, 2029: 4, 2030: 5
    ]

    static func badge(for date: Date) -> Badge {
        if let scheduled = schedule[key(for: date)] {
            return scheduled
        }
        if let festival = festivalBadge(for: date) {
            return festival
        }
        return Badge(text: lunarLabel(for: date), kind: .lunar)
    }

    /// 完整农历日期，如「农历九月十七」，供今日概览使用。
    static func fullLunarLabel(for date: Date) -> String {
        let components = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = components.month, let day = components.day else { return "" }
        let prefix = (components.isLeapMonth == true ? "闰" : "") + lunarMonths[month - 1]
        return "农历" + prefix + lunarDays[day - 1]
    }

    static func lunarMonthName(for date: Date) -> String {
        guard let interval = gregorian.dateInterval(of: .month, for: date),
              let middle = gregorian.date(byAdding: .day, value: 14, to: interval.start) else {
            return ""
        }
        let components = chinese.dateComponents([.month, .isLeapMonth], from: middle)
        guard let month = components.month else { return "" }
        return (components.isLeapMonth == true ? "闰" : "") + lunarMonths[month - 1]
    }

    private static func key(for date: Date) -> Int {
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }

    private static func festivalBadge(for date: Date) -> Badge? {
        let components = gregorian.dateComponents([.month, .day], from: date)
        guard let month = components.month,
              let day = components.day else { return nil }

        if month == 1, day == 1 { return Badge(text: "元旦", kind: .festival) }
        if month == 5, day == 1 { return Badge(text: "劳动节", kind: .festival) }
        if month == 10, day == 1 { return Badge(text: "国庆节", kind: .festival) }
        if isQingming(date) { return Badge(text: "清明节", kind: .festival) }

        if isLunarDate(date, month: 5, day: 5) {
            return Badge(text: "端午节", kind: .festival)
        }
        if isLunarDate(date, month: 8, day: 15) {
            return Badge(text: "中秋节", kind: .festival)
        }
        if isLunarDate(date, month: 1, day: 1) {
            return Badge(text: "春节", kind: .festival)
        }

        if isLunarNewYearsEve(date) {
            return Badge(text: "除夕", kind: .festival)
        }
        return nil
    }

    /// 农历月的第一天（正月初一、二月一……），日历用它给这类日子加重显示。
    static func isLunarMonthStart(_ date: Date) -> Bool {
        chinese.dateComponents([.day], from: date).day == 1
    }

    static func isLunarDate(_ date: Date, month: Int, day: Int) -> Bool {
        let lunar = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        return lunar.isLeapMonth != true && lunar.month == month && lunar.day == day
    }

    static func isQingming(_ date: Date) -> Bool {
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return components.month == 4 && components.day == qingmingDays[components.year ?? 0]
    }

    static func isLunarNewYearsEve(_ date: Date) -> Bool {
        let lunar = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard lunar.month == 12, lunar.isLeapMonth != true, lunar.day == 29 || lunar.day == 30 else {
            return false
        }
        guard let next = gregorian.date(byAdding: .day, value: 1, to: date) else { return false }
        let nextLunar = chinese.dateComponents([.month, .day, .isLeapMonth], from: next)
        return nextLunar.month == 1 && nextLunar.day == 1 && nextLunar.isLeapMonth != true
    }

    private static func lunarLabel(for date: Date) -> String {
        let components = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = components.month, let day = components.day else { return "" }
        let prefix = components.isLeapMonth == true ? "闰" : ""
        if day == 1 {
            return prefix + lunarMonths[month - 1]
        }
        return lunarDays[day - 1]
    }
}
