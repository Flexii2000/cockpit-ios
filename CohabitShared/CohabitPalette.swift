import SwiftUI

/// Die Farben von coHabit (Vertrag §2.1) - fuer App und Kachel dieselben.
///
/// Jede Palettenfarbe hat vier Stufen: die Flaeche (hell/dunkel je nach
/// Erscheinungsbild), den Akzent fuer Balken und Zellen und die kraeftige
/// Stufe fuer Text auf der hellen Flaeche. Auf der dunklen Flaeche traegt die
/// Tinte den Text - die kraeftige Stufe waere dort zu dunkel.
struct PaletteColor: Sendable {
    let surfaceLight: UInt32
    let accentHex: UInt32
    let strongHex: UInt32
    let surfaceDark: UInt32

    /// Die Kartenflaeche in der Co-Habit-Farbe.
    var surface: Color { .adaptive(light: surfaceLight, dark: surfaceDark) }
    /// Balken, Zellen, der angeschnittene Kreis.
    var accent: Color { Color(hex: accentHex) }
    /// Text auf der Flaeche.
    var onSurface: Color { .adaptive(light: strongHex, dark: 0xF2F0FA) }
    var strong: Color { Color(hex: strongHex) }
}

extension PaletteKey {
    var colors: PaletteColor {
        switch self {
        case .peach:      PaletteColor(surfaceLight: 0xFFD9C7, accentHex: 0xF2A07B, strongHex: 0xB5532A, surfaceDark: 0x4D3A31)
        case .mint:       PaletteColor(surfaceLight: 0xCFE8D5, accentHex: 0x7CC39A, strongHex: 0x2F7A52, surfaceDark: 0x2E4336)
        case .periwinkle: PaletteColor(surfaceLight: 0xD6DCFB, accentHex: 0x8F9CF2, strongHex: 0x3F4FC2, surfaceDark: 0x323A5C)
        case .butter:     PaletteColor(surfaceLight: 0xFFF0B3, accentHex: 0xF2D46B, strongHex: 0x8A6D00, surfaceDark: 0x4A4326)
        case .rose:       PaletteColor(surfaceLight: 0xFBD3E0, accentHex: 0xEE8FB0, strongHex: 0xA83A62, surfaceDark: 0x4A2F3A)
        case .aqua:       PaletteColor(surfaceLight: 0xCDEFF1, accentHex: 0x6CCFD6, strongHex: 0x1E7F87, surfaceDark: 0x27454A)
        }
    }

    var title: String {
        switch self {
        case .peach: "Pfirsich"
        case .mint: "Minze"
        case .periwinkle: "Flieder"
        case .butter: "Butter"
        case .rose: "Rosé"
        case .aqua: "Aqua"
        }
    }
}

/// Die App-Farben (Vertrag §2.1). Dunkel folgt dem System.
enum Ink {
    static let background = Color.adaptive(light: 0xF3F0FB, dark: 0x14131C)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x1F1D2B)
    static let ink = Color.adaptive(light: 0x1C1B2E, dark: 0xF2F0FA)
    /// Text auf einer Flaeche in Tinte - die Umkehrung.
    static let onInk = Color.adaptive(light: 0xFFFFFF, dark: 0x1C1B2E)
    static let muted = Color.adaptive(light: 0x6E6A80, dark: 0xA19DB5)
    static let accent = Color.adaptive(light: 0x5B3FD9, dark: 0x8A74F0)
    static let accentSoft = Color.adaptive(light: 0xE7E1FB, dark: 0x2C2645)
    static let danger = Color.adaptive(light: 0xB3261E, dark: 0xF2B8B5)
    /// Leere Zellen, Spuren von Balken.
    static let track = Color.adaptive(light: 0xEFECF7, dark: 0x2A2838)
}

extension Font {
    /// Grosse Kennzahlen: schwarz, mit gleich breiten Ziffern (Vertrag §5.1).
    static func figure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).monospacedDigit()
    }

    /// Ueberschriften: sehr fett.
    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy)
    }
}

/// Der angeschnittene Kreis in einer Kartenecke (Vertrag §5.1).
struct CornerCircle: View {
    enum Corner { case topTrailing, bottomLeading, bottomTrailing, topLeading }

    let color: Color
    var corner: Corner = .topTrailing
    var size: CGFloat = 120
    var inset: CGFloat = 0.35

    var body: some View {
        GeometryReader { proxy in
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .position(position(in: proxy.size))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func position(in bounds: CGSize) -> CGPoint {
        let offset = size * inset
        switch corner {
        case .topTrailing: return CGPoint(x: bounds.width - size / 2 + offset, y: size / 2 - offset)
        case .bottomLeading: return CGPoint(x: size / 2 - offset, y: bounds.height - size / 2 + offset)
        case .bottomTrailing: return CGPoint(x: bounds.width - size / 2 + offset, y: bounds.height - size / 2 + offset)
        case .topLeading: return CGPoint(x: size / 2 - offset, y: size / 2 - offset)
        }
    }
}
