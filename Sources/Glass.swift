import AppKit
import SwiftUI

/// 桌面卡片的底面材质：实心（纯白）或四档系统毛玻璃。
enum CardMaterial: Int, CaseIterable, Identifiable {
    case solid = 0
    case ultraThin = 1
    case thin = 2
    case regular = 3
    case thick = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .solid: return "实心"
        case .ultraThin: return "超细"
        case .thin: return "轻"
        case .regular: return "标准"
        case .thick: return "浓"
        }
    }

    var isGlass: Bool { self != .solid }

    var help: String {
        switch self {
        case .solid: return "不透明的纯白卡片"
        case .ultraThin: return "最透，桌布几乎原样透过来"
        case .thin: return "轻微磨砂"
        case .regular: return "标准磨砂，文字最清楚"
        case .thick: return "最厚，接近实心的雾面"
        }
    }
}

/// 卡片底面：材质 + 一层可调浓度的白纱（保证文字在任意桌布上都读得清）。
struct CardBackground: View {
    let material: CardMaterial
    /// 0 = 最乳白，1 = 最通透。
    let clarity: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            base
            veil
        }
    }

    @ViewBuilder
    private var base: some View {
        switch material {
        case .solid:
            colorScheme == .light ? Color.white : Color(nsColor: .windowBackgroundColor)
        case .ultraThin:
            Rectangle().fill(.ultraThinMaterial)
        case .thin:
            Rectangle().fill(.thinMaterial)
        case .regular:
            Rectangle().fill(.regularMaterial)
        case .thick:
            Rectangle().fill(.thickMaterial)
        }
    }

    private var veil: some View {
        Rectangle().fill(veilColor)
    }

    private var veilColor: Color {
        guard material.isGlass else { return Color.clear }
        let strength = (1 - clarity) * 0.72
        return colorScheme == .light
            ? Color.white.opacity(strength)
            : Color.black.opacity(strength)
    }
}

extension Color {
    /// 玻璃卡片的描边要更亮一点，否则会糊进桌布里。
    static func cardBorder(material: CardMaterial, colorScheme: ColorScheme) -> Color {
        if material.isGlass {
            return colorScheme == .light
                ? Color.white.opacity(0.42)
                : Color.white.opacity(0.20)
        }
        return colorScheme == .light ? Color.black.opacity(0.07) : Color.white.opacity(0.14)
    }
}
