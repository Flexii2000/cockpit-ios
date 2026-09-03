import SwiftUI

/// Wie ein Wert gegen sein Ziel dasteht.
enum MacroTone: Sendable {
    case neutral, near, good, warn, bad

    /// Dieselben Verlaeufe wie in der Weboberflaeche (`#gauge-…` in
    /// `food/.../index.html`) - dieselbe Zahl soll in App und Browser nicht
    /// unterschiedlich eingefaerbt sein.
    var gradient: [Color] {
        switch self {
        case .neutral, .near: [Color(hex: 0x8BA3FF), Color(hex: 0x4C6EF5)]
        case .good:           [Color(hex: 0x8EE09B), Color(hex: 0x43A75A)]
        case .warn:           [Color(hex: 0xFFD68A), Color(hex: 0xF59F26)]
        case .bad:            [Color(hex: 0xFF938F), Color(hex: 0xDC3C39)]
        }
    }
}

/// In welche Richtung ein Ziel gemeint ist.
enum TargetDirection: Sendable {
    /// Mindestwert - darueber ist das Ziel erreicht (Eiweiss).
    case floor
    /// Obergrenze - darueber ist es zu viel (kcal, Fett, Kohlenhydrate).
    case ceiling
}

/// Die drei Makros unter dem kcal-Tacho.
enum Macro: String, CaseIterable, Identifiable, Sendable {
    // Reihenfolge wie in der Weboberflaeche: Eiweiss, Fett, Kohlenhydrate.
    case protein, fat, carbs

    var id: String { rawValue }

    /// Fuer den Sperrbildschirm, wo eine Zeile drei Werte tragen muss.
    var short: String {
        switch self {
        case .protein: "E"
        case .fat:     "F"
        case .carbs:   "KH"
        }
    }

    var label: String {
        switch self {
        case .protein: "Eiweiß"
        case .fat:     "Fett"
        case .carbs:   "Kohlenhydrate"
        }
    }

    /// Eiweiss ist ein Mindestwert, Fett und Kohlenhydrate sind Obergrenzen.
    /// Ohne diese Unterscheidung waere die Haelfte der Einfaerbungen falsch
    /// herum.
    var direction: TargetDirection {
        switch self {
        case .protein: .floor
        case .fat, .carbs: .ceiling
        }
    }

    /// Wie weit ueber dem Ziel noch gelb ist; darueber rot. Vorgabe waren
    /// 100 kcal, in Gramm umgerechnet: Kohlenhydrate 4 kcal/g -> 25 g,
    /// Fett 9 kcal/g -> gut 11 g.
    var tolerance: Double {
        switch self {
        case .protein: 0
        case .fat:     11
        case .carbs:   25
        }
    }

    func value(_ nutrients: Nutrients) -> Double {
        switch self {
        case .protein: nutrients.proteinG
        case .fat:     nutrients.fatG
        case .carbs:   nutrients.carbsG
        }
    }
}

enum NutritionTone {

    /// Toleranz fuer das kcal-Ziel.
    static let kcalTolerance: Double = 100

    /// Uebernommen aus `toneFor()` der Weboberflaeche.
    static func tone(consumed: Double, target: Double,
                     direction: TargetDirection, tolerance: Double) -> MacroTone {
        switch direction {
        case .floor:
            if consumed >= target { return .good }
            // Knapp darunter ist etwas anderes als weit darunter - aber beides
            // ist kein Fehler, deshalb kein Warnton.
            return target > 0 && consumed / target >= 0.8 ? .near : .neutral
        case .ceiling:
            let over = consumed - target
            if over <= 0 { return .neutral }
            return over <= tolerance ? .warn : .bad
        }
    }

    static func tone(for macro: Macro, consumed: Nutrients, targets: Nutrients) -> MacroTone {
        tone(consumed: macro.value(consumed), target: macro.value(targets),
             direction: macro.direction, tolerance: macro.tolerance)
    }

    static func kcalTone(consumed: Nutrients, targets: Nutrients) -> MacroTone {
        tone(consumed: consumed.kcal, target: targets.kcal,
             direction: .ceiling, tolerance: kcalTolerance)
    }
}
