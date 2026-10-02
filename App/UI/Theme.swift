import AppKit
import SwiftUI

/// La identidad de Parla en un solo sitio: el acento, el texto que va encima y
/// la letra del inglés. El panel y las tarjetas la reutilizarán cuando se
/// rediseñen.
enum Theme {

    /// Un color sRGB, para poder calcular contrastes en los tests.
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        /// Luminancia relativa, como la define WCAG.
        var luminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    enum Palette {
        /// Igual que `AccentColor` en el catálogo; un test lo vigila.
        static let accentLight = RGB(hex: 0xB84A26)
        static let accentDark = RGB(hex: 0xF0997B)
        static let onAccentLight = RGB(hex: 0xFFFFFF)
        static let onAccentDark = RGB(hex: 0x4A1B0C)
        /// Más vivo que el acento: el icono no lleva texto pequeño encima.
        static let iconBackground = RGB(hex: 0xD85A30)
        static let white = RGB(hex: 0xFFFFFF)
    }

    /// El acento del catálogo, el mismo que tiñe los controles.
    static let accent = Color.accentColor

    /// Texto e iconos sobre un relleno de acento.
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? Palette.onAccentDark.nsColor
            : Palette.onAccentLight.nsColor
    })

    /// El inglés, que es lo que se estudia, va en serif.
    static func english(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }

    static func contrastRatio(_ first: RGB, _ second: RGB) -> Double {
        let lighter = max(first.luminance, second.luminance)
        let darker = min(first.luminance, second.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
