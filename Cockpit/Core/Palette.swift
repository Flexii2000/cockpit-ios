import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Die Farben der Diagramme. Uebernommen aus den Weboberflaechen, damit
/// dieselbe Kurve in App und Browser nicht unterschiedlich aussieht.
enum Palette {
    static let measured = Color(hex: 0x4FC3F7)
    static let avg7     = Color(hex: 0x81C784)
    static let avg14    = Color(hex: 0xFFB74D)
    static let avg30    = Color(hex: 0xBA68C8)
    static let target   = Color(hex: 0xE57373)
    static let kcal     = Color(hex: 0xFFD54F)
    static let vacation = Color(hex: 0x7C9CFA)
}

extension WeightSeries {
    var color: Color {
        switch self {
        case .measured: Palette.measured
        case .avg7:     Palette.avg7
        case .avg14:    Palette.avg14
        case .avg30:    Palette.avg30
        case .target:   Palette.target
        }
    }
}
