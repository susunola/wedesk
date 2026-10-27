import Combine
import Foundation

/// 天气城市（由 Open-Meteo 地理编码搜索得到，不依赖定位权限）。
struct WeatherCity: Codable, Equatable, Identifiable, Hashable {
    let name: String
    let admin: String?
    let lat: Double
    let lon: Double

    var id: String { "\(name)|\(admin ?? "")|\(lat),\(lon)" }

    /// 地区后缀，用于区分同名城市；「苏州市」对「苏州」这类重复表述直接省略。
    var regionText: String? {
        guard let admin, !admin.isEmpty else { return nil }
        if admin == name || admin == name + "市" || admin == name + "区" { return nil }
        return admin
    }

    /// 搜索框为空时展示的常用城市。
    static let popular: [WeatherCity] = [
        WeatherCity(name: "北京", admin: "北京市", lat: 39.9042, lon: 116.4074),
        WeatherCity(name: "上海", admin: "上海市", lat: 31.2304, lon: 121.4737),
        WeatherCity(name: "广州", admin: "广东省", lat: 23.1291, lon: 113.2644),
        WeatherCity(name: "深圳", admin: "广东省", lat: 22.5431, lon: 114.0579),
        WeatherCity(name: "杭州", admin: "浙江省", lat: 30.2741, lon: 120.1551),
        WeatherCity(name: "成都", admin: "四川省", lat: 30.5728, lon: 104.0668),
    ]

    static let fallback = WeatherCity.popular[0]
}

struct WeatherNow: Codable, Equatable {
    var temperature: Double
    var apparent: Double
    var humidity: Double?
    var wind: Double?
    var code: Int
    var isDay: Bool
}

struct WeatherDay: Codable, Equatable, Identifiable {
    var id: String { dateKey }
    var dateKey: String
    var maxC: Double
    var minC: Double
    var code: Int
    var rainChance: Int?

    var date: Date? {
        Self.parser.date(from: dateKey)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 卡片上显示「今天 / 明天 / 周三」。
    var weekdayText: String {
        guard let date else { return dateKey }
        let delta = DateUtil.dayDelta(to: date)
        if delta == 0 { return "今天" }
        if delta == 1 { return "明天" }
        return DateUtil.weekdayName(date)
    }
}

struct WeatherSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var now: WeatherNow
    var days: [WeatherDay]

    var today: WeatherDay? { days.first }
}

/// WMO 天气码 → 中文描述与图标。
enum WeatherCondition {
    static func label(code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "晴" : "晴夜"
        case 1: return "晴间多云"
        case 2: return "局部多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 66, 67: return "冻雨"
        case 71: return "小雪"
        case 73: return "中雪"
        case 75: return "大雪"
        case 77: return "雪粒"
        case 80: return "小阵雨"
        case 81: return "阵雨"
        case 82: return "强阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷阵雨"
        case 96, 99: return "雷阵雨伴冰雹"
        default: return "未知"
        }
    }

    static func symbol(code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "snowflake"
        case 80, 81, 82: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }
}

/// 纯网络层，不依赖任何界面状态，便于单独验证。
enum WeatherRequest {
    static func search(_ keyword: String, completion: @escaping ([WeatherCity]) -> Void) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=8&language=zh&format=json")
        else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            var cities: [WeatherCity] = []
            if let data, let decoded = try? JSONDecoder().decode(GeoResponse.self, from: data) {
                cities = decoded.results.map { item in
                    WeatherCity(name: item.name, admin: item.admin1, lat: item.latitude, lon: item.longitude)
                }
            }
            DispatchQueue.main.async { completion(cities) }
        }
        task.resume()
    }

    static func fetch(city: WeatherCity, completion: @escaping (Result<WeatherSnapshot, Error>) -> Void) {
        guard let url = URL(string: endpoint(for: city)) else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<WeatherSnapshot, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                result = .failure(URLError(.badServerResponse))
            } else if let data,
                      let decoded = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data),
                      let snapshot = decoded.toSnapshot() {
                result = .success(snapshot)
            } else {
                result = .failure(URLError(.cannotParseResponse))
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }

    static func endpoint(for city: WeatherCity) -> String {
        let lat = String(format: "%.4f", city.lat)
        let lon = String(format: "%.4f", city.lon)
        return "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&timezone=auto&forecast_days=4"
    }

    static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "数据异常" }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost:
            return "网络不可用"
        case .timedOut:
            return "请求超时"
        case .badServerResponse:
            return "服务暂时不可用"
        case .cannotParseResponse:
            return "数据异常"
        default:
            return "获取失败"
        }
    }
}

// MARK: - Store

final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    @Published private(set) var city: WeatherCity
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    static let cityKey = "wedesk.weather.city.v1"
    static let snapshotKey = "wedesk.weather.snapshot.v1"

    private let refreshInterval: TimeInterval = 20 * 60
    private var timer: Timer?
    private var searchGeneration = 0
    private var inFlight = false

    private init() {
        city = WeatherStore.loadCity()
        snapshot = WeatherStore.loadSnapshot()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { _ in
            WeatherStore.shared.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var hasData: Bool { snapshot != nil }

    var updatedText: String {
        guard let snapshot else { return "尚未获取" }
        return "更新于 \(DateUtil.timeOnly(snapshot.fetchedAt))"
    }

    /// 缓存超过两个刷新周期视为过期：卡片仍显示旧值，只做提醒。
    var isStale: Bool {
        guard let snapshot else { return true }
        return Date().timeIntervalSince(snapshot.fetchedAt) > refreshInterval * 2
    }

    /// 概览卡用的紧凑一行，如「晴 12°」。
    var summaryText: String? {
        guard let now = snapshot?.now else { return nil }
        return "\(WeatherCondition.label(code: now.code, isDay: now.isDay)) \(DateUtil.temperature(now.temperature))"
    }

    var summarySymbol: String? {
        guard let now = snapshot?.now else { return nil }
        return WeatherCondition.symbol(code: now.code, isDay: now.isDay)
    }

    // MARK: - Refresh

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        isLoading = true
        errorMessage = nil

        let target = city
        WeatherRequest.fetch(city: target) { [weak self] result in
            guard let self else { return }
            self.inFlight = false
            self.isLoading = false
            // 期间换过城市，旧响应直接丢弃。
            guard target == self.city else { return }
            switch result {
            case .success(let loaded):
                self.snapshot = loaded
                self.errorMessage = nil
                WeatherStore.save(loaded, to: Self.snapshotKey)
            case .failure(let error):
                // 失败时保留上一次数据，只提示原因。
                self.errorMessage = WeatherRequest.describe(error)
            }
        }
    }

    /// 首次用到时才拉，避免没有开启天气卡也发请求。
    func refreshIfNeeded() {
        if snapshot == nil || isStale {
            refresh()
        }
    }

    func setCity(_ newCity: WeatherCity) {
        guard newCity != city else { return }
        city = newCity
        WeatherStore.save(newCity, to: Self.cityKey)
        snapshot = nil
        errorMessage = nil
        refresh()
    }

    // MARK: - City search

    /// 输入后延迟搜索；空关键词直接返回常用城市，不发请求。
    func searchCities(_ text: String, completion: @escaping ([WeatherCity]) -> Void) {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            completion(WeatherCity.popular)
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.searchGeneration == generation else { return }
            WeatherRequest.search(keyword) { found in
                guard self.searchGeneration == generation else { return }
                completion(found.isEmpty ? WeatherCity.popular : found)
            }
        }
    }

    /// 关键词清空时作废所有在途结果。
    func cancelSearching() {
        searchGeneration += 1
    }

    // MARK: - Persistence

    private static func loadCity() -> WeatherCity {
        guard let data = UserDefaults.standard.data(forKey: cityKey),
              let decoded = try? JSONDecoder().decode(WeatherCity.self, from: data)
        else { return WeatherCity.fallback }
        return decoded
    }

    private static func loadSnapshot() -> WeatherSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    private static func save(_ value: Encodable, to key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - DTOs

struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double?
        let apparent_temperature: Double?
        let relative_humidity_2m: Double?
        let wind_speed_10m: Double?
        let weather_code: Int?
        let is_day: Int?
    }

    struct Daily: Decodable {
        let time: [String]?
        let weather_code: [Int?]?
        let temperature_2m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let precipitation_probability_max: [Double?]?
    }

    let current: Current?
    let daily: Daily?

    func toSnapshot() -> WeatherSnapshot? {
        guard let current, let temperature = current.temperature_2m, let code = current.weather_code else {
            return nil
        }

        let now = WeatherNow(
            temperature: temperature,
            apparent: current.apparent_temperature ?? temperature,
            humidity: current.relative_humidity_2m,
            wind: current.wind_speed_10m,
            code: code,
            isDay: (current.is_day ?? 1) == 1
        )

        let day = daily
        let times = day?.time ?? []
        var days: [WeatherDay] = []
        for index in times.indices {
            let maxC = day?.temperature_2m_max?.value(at: index).flatMap { $0 }
            let minC = day?.temperature_2m_min?.value(at: index).flatMap { $0 }
            let dayCode = day?.weather_code?.value(at: index).flatMap { $0 }
            let rain = day?.precipitation_probability_max?.value(at: index).flatMap { $0 }

            days.append(WeatherDay(
                dateKey: times[index],
                maxC: maxC ?? temperature,
                minC: minC ?? temperature,
                code: dayCode ?? code,
                rainChance: rain.map { Int($0.rounded()) }
            ))
        }

        guard !days.isEmpty else { return nil }
        return WeatherSnapshot(fetchedAt: Date(), now: now, days: days)
    }
}

struct GeoResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let admin1: String?
        let latitude: Double
        let longitude: Double
    }

    let results: [GeoResponse.Result]

    private enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([Result].self, forKey: .results) ?? []
    }
}

private extension Array {
    /// 越界安全取值：Open-Meteo 偶发数组长度不一致。
    func value(at index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
