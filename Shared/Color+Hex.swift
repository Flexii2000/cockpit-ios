import SwiftUI
import UIKit

// Liegt in Shared/, weil das Widget dieselben Farben braucht - der Rest von
// Palette.swift kann nicht mit, dort steht eine Erweiterung auf WeightSeries,
// und die gibt es im Widget nicht.
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Eine Farbe, die dem Erscheinungsbild folgt.
    ///
    /// Noetig, weil die Diagrammfarben aus den Weboberflaechen stammen - und
    /// die sind dunkel. Dieselben hellen Pastelltoene auf weissem Grund haben
    /// zu wenig Kontrast; im Hellmodus kommt deshalb die kraeftigere Stufe
    /// derselben Farbe zum Zug.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
