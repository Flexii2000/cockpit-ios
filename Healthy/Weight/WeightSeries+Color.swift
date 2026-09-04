import SwiftUI

/// Welche Farbe aus der Palette zu welcher Reihe gehoert.
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
