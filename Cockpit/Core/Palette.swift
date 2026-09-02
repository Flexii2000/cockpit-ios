import SwiftUI
import UIKit

/// Die Farben der Diagramme.
///
/// Der Dunkelwert ist jeweils der aus der Weboberflaeche - dieselbe Kurve
/// sieht in App und Browser gleich aus. Der Hellwert ist dieselbe Farbe, nur
/// kraeftiger.
enum Palette {
    static let measured = Color.adaptive(light: 0x0288D1, dark: 0x4FC3F7)
    static let avg7     = Color.adaptive(light: 0x388E3C, dark: 0x81C784)
    static let avg14    = Color.adaptive(light: 0xF57C00, dark: 0xFFB74D)
    static let avg30    = Color.adaptive(light: 0x7B1FA2, dark: 0xBA68C8)
    static let target   = Color.adaptive(light: 0xD32F2F, dark: 0xE57373)
    static let kcal     = Color.adaptive(light: 0xF9A825, dark: 0xFFD54F)
    static let vacation = Color.adaptive(light: 0x5C7CFA, dark: 0x7C9CFA)
    /// Ueber dem Ziel - im Verlauf des Kalorienzaehlers.
    static let over     = Color.adaptive(light: 0xD32F2F, dark: 0xEF5350)
}

extension WeightSeries {
    var color: Color {
        switch self {
        case .measured: Palette.measured
        case .avg7:     Palette.avg7
        case .avg14:    Palette.avg14
        case .avg30:    Palette.avg30
        case .target:   Palette.target
        case .kcal:     Palette.kcal
        }
    }
}
