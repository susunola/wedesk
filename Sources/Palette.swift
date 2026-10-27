import AppKit
import SwiftUI

enum Palette {
    struct Accent: Identifiable, Equatable {
        let id: Int
        let name: String
        let color: Color
    }

    static let accents: [Accent] = [
        Accent(id: 0, name: "蓝色", color: Color(red: 0.12, green: 0.44, blue: 0.88)),
        Accent(id: 1, name: "青色", color: Color(red: 0.04, green: 0.63, blue: 0.75)),
        Accent(id: 2, name: "松绿", color: Color(red: 0.10, green: 0.60, blue: 0.41)),
        Accent(id: 3, name: "橙色", color: Color(red: 0.87, green: 0.47, blue: 0.16)),
        Accent(id: 4, name: "赤陶", color: Color(red: 0.70, green: 0.32, blue: 0.18)),
        Accent(id: 5, name: "玫红", color: Color(red: 0.84, green: 0.29, blue: 0.47)),
        Accent(id: 6, name: "靛紫", color: Color(red: 0.41, green: 0.35, blue: 0.89)),
        Accent(id: 7, name: "石墨", color: Color(red: 0.30, green: 0.34, blue: 0.39))
    ]

    static func accent(at index: Int) -> Accent {
        guard index >= 0 && index < accents.count else { return accents[0] }
        return accents[index]
    }

    static func swatch(for color: Color) -> NSImage {
        let diameter: CGFloat = 11
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        NSColor(color).setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

let wenkaiRegular = "LXGW WenKai"
let wenkaiMedium = "LXGW WenKai Medium"

extension Font {
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black:
            return .custom(wenkaiMedium, size: size)
        default:
            return .custom(wenkaiRegular, size: size)
        }
    }
}
