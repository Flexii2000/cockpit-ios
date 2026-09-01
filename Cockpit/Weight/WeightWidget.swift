import SwiftUI

/// Wie eine Kachel eingefaerbt wird.
enum Tone: Sendable {
    case good, warn, bad

    var color: Color {
        switch self {
        case .good: .green
        case .warn: .orange
        case .bad:  .red
        }
    }
}

/// Die Kacheln über dem Diagramm.
///
/// Eins zu eins die Registry aus der Weboberflaeche
/// (`weight-app/.../static/app.js`, `const WIDGETS`). Bewusst als Enum und
/// nicht als Tabelle von Closures: so ist jede Kachel an einer Stelle
/// vollstaendig beschrieben, und der Compiler merkt, wenn eine fehlt.
enum WeightWidget: String, CaseIterable, Identifiable, Sendable {
    case current, goal, diff, bmi
    case avg7, avg14, avg30, target, corridor, targetDate
    case startWeight, recordingStart, lastEntry, totalDiff
    case lost, remaining, progress, daysToTarget

    var id: String { rawValue }

    /// Die vier stehen immer oben und lassen sich nicht entfernen - wie im Web.
    /// Der Server speichert deshalb auch nur die Zusaetze.
    static let base: [WeightWidget] = [.current, .goal, .diff, .bmi]

    /// Koerpergroesse fuer den BMI. Steht so auch in der Weboberflaeche
    /// (`HEIGHT_M`); eine weitere Personalisierung braucht diese App nicht.
    static let heightM = 1.94

    var label: String {
        switch self {
        case .current:        "Aktuell"
        case .goal:           "Ziel"
        case .diff:           "Differenz z. Target"
        case .bmi:            "BMI"
        case .avg7:           "7-Tage-Mittel"
        case .avg14:          "14-Tage-Mittel"
        case .avg30:          "30-Tage-Mittel"
        case .target:         "Target heute"
        case .corridor:       "Zielkorridor"
        case .targetDate:     "Zieltag"
        case .startWeight:    "Startgewicht"
        case .recordingStart: "Start der Aufzeichnung"
        case .lastEntry:      "Letzte Messung"
        case .totalDiff:      "Gesamtdifferenz"
        case .lost:           "Bisher abgenommen"
        case .remaining:      "Noch bis Ziel"
        case .progress:       "Fortschritt"
        case .daysToTarget:   "Tage bis Zieltag"
        }
    }

    func value(_ s: WeightSummary) -> String {
        switch self {
        case .current:        s.current.kg
        case .goal:           s.goalWeight.kg
        case .diff:
            if let current = s.current, let target = s.target {
                (current - target).signedKg
            } else { "–" }
        case .bmi:
            if let bmi = Self.bmi(s) { String(format: "%.1f", bmi) } else { "–" }
        case .avg7:           s.avg7.kg
        case .avg14:          s.avg14.kg
        case .avg30:          s.avg30.kg
        case .target:         s.target.kg
        case .corridor:
            if let lower = s.corridorLower, let upper = s.corridorUpper {
                String(format: "%.1f–%.1f kg", lower, upper)
            } else { "–" }
        case .targetDate:     s.targetDate.short
        case .startWeight:    s.startWeight.kg
        case .recordingStart: s.recordingStart.short
        case .lastEntry:      s.date.short
        case .totalDiff:
            if let current = s.current, let start = s.startWeight {
                (current - start).signedKg
            } else { "–" }
        case .lost:
            if let current = s.current, let start = s.startWeight {
                (start - current).kg
            } else { "–" }
        case .remaining:
            if let current = s.current, let goal = s.goalWeight {
                max(current - goal, 0).kg
            } else { "–" }
        case .progress:
            if let start = s.startWeight, let current = s.current,
               let goal = s.goalWeight, start - goal > 0 {
                "\(Int(((start - current) / (start - goal) * 100).rounded())) %"
            } else { "–" }
        case .daysToTarget:
            if let targetDate = s.targetDate {
                targetDate.daysFromToday() <= 0 ? "erreicht" : "\(targetDate.daysFromToday())"
            } else { "–" }
        }
    }

    func tone(_ s: WeightSummary) -> Tone? {
        switch self {
        case .diff:
            guard let current = s.current, let target = s.target else { return nil }
            // In der Haltephase zaehlt der Korridor, nicht der Tageswert der
            // Kurve: sonst faerbte sich die Kachel bei jeder normalen
            // Tagesschwankung um, obwohl genau die der Normalfall ist.
            if s.isInCorridor { return .good }
            let diff = current - target
            if diff <= 0 { return .good }
            return diff <= 0.75 ? .warn : .bad
        case .bmi:
            guard let bmi = Self.bmi(s) else { return nil }
            // WHO: <18,5 Untergewicht, <25 Normal, <30 Uebergewicht, sonst Adipositas
            if bmi < 18.5 || bmi >= 30 { return .bad }
            return bmi >= 25 ? .warn : .good
        case .corridor:
            // Ohne erreichten Korridor bewusst ungefaerbt: die Zahlen stehen
            // dann zwar schon da, sind aber noch kein Massstab.
            guard s.corridorReachedOn != nil, s.current != nil else { return nil }
            return s.isInCorridor ? .good : .warn
        case .totalDiff:
            guard let current = s.current, let start = s.startWeight else { return nil }
            return current <= start ? .good : .bad
        default:
            return nil
        }
    }

    private static func bmi(_ s: WeightSummary) -> Double? {
        guard let current = s.current else { return nil }
        return current / (heightM * heightM)
    }
}
