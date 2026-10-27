import AppKit
import Combine
import SwiftUI

enum WeatherStyle {
    static let rain = Color(red: 0.20, green: 0.52, blue: 0.84)
}

/// 天气卡：当前天气、体感与湿度风力、未来三日预报、城市切换与手动刷新。
struct WeatherWidgetRoot: View {
    @EnvironmentObject private var store: TodoStore
    let onHide: () -> Void

    var body: some View {
        StandaloneWidgetCard(kind: .weather, onHide: onHide) {
            WeatherPanel(accent: store.accent)
        }
    }
}

struct WeatherPanel: View {
    @ObservedObject private var weather = WeatherStore.shared
    let accent: Color

    @State private var showCityPicker = false
    @State private var isRefreshingPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let snapshot = weather.snapshot {
                // 主体信息区都不是按钮，整块都能当握把拖动卡片。
                mainBlock(snapshot)
                    .background(WindowDragRegion())
                metricsRow(snapshot)
                    .background(WindowDragRegion())
                rule
                forecastBlock(snapshot)
                    .background(WindowDragRegion())
            } else if weather.isLoading {
                stateBlock(symbol: "cloud", title: "正在获取天气…", note: "\(weather.city.name) · 通常只需一两秒")
            } else {
                stateBlock(
                    symbol: "wifi.exclamationmark",
                    title: weather.errorMessage ?? "暂时拿不到天气",
                    note: "可以点右上角重试，或换个城市"
                )
            }

            Spacer(minLength: 0)

            footnote
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .onAppear {
            weather.refreshIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                showCityPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.app(size: 8.5, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.8))

                    Text(weather.city.name)
                        .font(.app(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.86))
                        .lineLimit(1)

                    if let region = weather.city.regionText, region != weather.city.name {
                        Text(region)
                            .font(.app(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.down")
                        .font(.app(size: 7.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(showCityPicker ? 0.09 : 0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("选择城市")
            .popover(isPresented: $showCityPicker, arrowEdge: .bottom) {
                WeatherCityPickerPanel(accent: accent, isPresented: $showCityPicker)
                    .frame(width: 244)
            }

            Spacer(minLength: 4)

            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            weather.refresh()
            isRefreshingPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                isRefreshingPulse = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.app(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isRefreshingPulse ? 360 : 0))
                .animation(.easeInOut(duration: 0.7), value: isRefreshingPulse)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(weather.isLoading)
        .opacity(weather.isLoading ? 0.45 : 1)
        .help("立即刷新")
    }

    // MARK: - Main

    private func mainBlock(_ snapshot: WeatherSnapshot) -> some View {
        let now = snapshot.now
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: WeatherCondition.symbol(code: now.code, isDay: now.isDay))
                .font(.app(size: 34, weight: .regular))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(accent)
                .frame(width: 48, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(DateUtil.temperature(now.temperature))
                    .font(.app(size: 34, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .lineLimit(1)

                Text("\(WeatherCondition.label(code: now.code, isDay: now.isDay)) · 体感 \(DateUtil.temperature(now.apparent))")
                    .font(.app(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let today = snapshot.today {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(DateUtil.temperature(today.maxC)) / \(DateUtil.temperature(today.minC))")
                        .font(.app(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary.opacity(0.72))

                    Text("今日")
                        .font(.app(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .fixedSize()
            }
        }
        .padding(.top, 2)
    }

    private func metricsRow(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 6) {
            metric(symbol: "humidity", value: snapshot.now.humidity.map { "\(Int($0.rounded()))%" } ?? "--", label: "湿度")
            metric(symbol: "wind", value: snapshot.now.wind.map { "\(Int($0.rounded())) km/h" } ?? "--", label: "风速")
            if let rain = snapshot.today?.rainChance {
                metric(symbol: "drop", value: "\(rain)%", label: "降水")
            } else {
                metric(symbol: "sun.max", value: snapshot.days.count > 1 ? "\(snapshot.days.count - 1) 日" : "--", label: "预报")
            }
        }
    }

    private func metric(symbol: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.app(size: 9.5, weight: .medium))
                .foregroundStyle(accent.opacity(0.75))

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.app(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)

                Text(label)
                    .font(.app(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Forecast

    private func forecastBlock(_ snapshot: WeatherSnapshot) -> some View {
        let upcoming = snapshot.days.dropFirst().prefix(3)
        return VStack(alignment: .leading, spacing: 1) {
            sectionTitle("未来预报")

            if upcoming.isEmpty {
                Text("暂时没有更多预报")
                    .font(.app(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(upcoming)) { day in
                    forecastRow(day)
                }
            }
        }
    }

    private func forecastRow(_ day: WeatherDay) -> some View {
        HStack(spacing: 8) {
            Text(day.weekdayText)
                .font(.app(size: 10.5))
                .foregroundStyle(Color.primary.opacity(0.75))
                .frame(width: 42, alignment: .leading)
                .lineLimit(1)

            Image(systemName: WeatherCondition.symbol(code: day.code))
                .font(.app(size: 10.5, weight: .regular))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(accent)
                .frame(width: 18)

            Text(WeatherCondition.label(code: day.code))
                .font(.app(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let rain = day.rainChance, rain > 0 {
                Text("\(rain)%")
                    .font(.app(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(WeatherStyle.rain.opacity(0.9))
            }

            Text("\(DateUtil.temperature(day.minC)) / \(DateUtil.temperature(day.maxC))")
                .font(.app(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(0.72))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 4)
    }

    // MARK: - States

    private func stateBlock(symbol: String, title: String, note: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.app(size: 22, weight: .regular))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(.secondary)
                .frame(height: 30)

            Text(title)
                .font(.app(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)

            Text(note)
                .font(.app(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !weather.isLoading {
                Button("重试") { weather.refresh() }
                    .buttonStyle(.plain)
                    .font(.app(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent))
                    .contentShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var footnote: some View {
        HStack(spacing: 5) {
            if weather.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            }

            Text(footnoteText)
                .font(.app(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var footnoteText: String {
        if let error = weather.errorMessage {
            return "\(error) · \(weather.updatedText)"
        }
        if weather.isStale {
            return "\(weather.updatedText) · 数据可能已过期"
        }
        return weather.updatedText
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 12, weight: .semibold))
            .padding(.top, 1)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }
}

// MARK: - City picker

private struct WeatherCityPickerPanel: View {
    @ObservedObject private var weather = WeatherStore.shared
    let accent: Color
    @Binding var isPresented: Bool

    @State private var keyword = ""
    @State private var results = WeatherCity.popular
    @State private var searching = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("切换城市")
                .font(.app(size: 12.5, weight: .semibold))

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.app(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField("拼音或中文城市名", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.app(size: 11.5))
                    .focused($fieldFocused)
                    .onSubmit(acceptFirstResult)

                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.app(size: 10, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清空")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .onChange(of: keyword) { _, value in
                searching = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                weather.searchCities(value) { found in
                    searching = false
                    results = found
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    if !keyword.isEmpty {
                        Text(searching ? "搜索中…" : "搜索结果")
                            .font(.app(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 2)
                    }

                    ForEach(results) { city in
                        cityRow(city)
                    }
                }
            }
            .frame(maxHeight: 178)
        }
        .padding(12)
        .onAppear {
            fieldFocused = true
        }
    }

    private func cityRow(_ city: WeatherCity) -> some View {
        let isCurrent = city == weather.city

        return Button {
            weather.setCity(city)
            isPresented = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.app(size: 10.5, weight: .regular))
                    .foregroundStyle(isCurrent ? accent : Color.secondary.opacity(0.45))

                VStack(alignment: .leading, spacing: 1) {
                    Text(city.name)
                        .font(.app(size: 11.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(isCurrent ? 0.9 : 0.78))
                        .lineLimit(1)

                    if let region = city.regionText {
                        Text(region)
                            .font(.app(size: 8.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrent ? accent.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func acceptFirstResult() {
        guard let first = results.first else { return }
        weather.setCity(first)
        isPresented = false
    }
}
