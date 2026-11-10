import SwiftUI

extension MacroTone {

    /// Die Farbe einer Makro-Zeile auf der Uhr (seit 10.11.): rot, gelb, gruen
    /// wie auf dem iPhone, aber aus Systemfarben - die Verlaeufe des iPhones
    /// (`MacroTone+Gradient.swift`) brauchen `Color(hex:)`, und das baut auf
    /// der Uhr nicht.
    var watchColor: Color {
        switch self {
        case .neutral, .near: .blue
        case .good:           .green
        case .warn:           .yellow
        case .bad:            .red
        }
    }
}

/// Der Text einer Makro-Zeile unter dem kcal-Bogen der Uhr: „E 96/195“
/// (Vertrag §11.1) - gegessen und Ziel in ganzen Gramm, ohne Einheit, weil die
/// Zeile schmal ist.
enum WatchMacroText {

    static func label(_ macro: Macro, consumed: Nutrients, targets: Nutrients) -> String {
        "\(macro.short) \(Int(macro.value(consumed).rounded()))/\(Int(macro.value(targets).rounded()))"
    }
}
