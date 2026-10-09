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

/// Was eine Kachel sehen darf: die Gewichts-Summary und - fuer die drei
/// Energie-Kacheln - die Energie-Summary des Weight Trackers.
struct TileInput: Sendable {
    let weight: WeightSummary
    /// `nil`, solange der Dienst keine Energie kennt (aelterer Dienst, keine
    /// Uhr) - dann zeigen die Energie-Kacheln „–", die anderen wie immer.
    let energy: EnergySummary?

    init(weight: WeightSummary, energy: EnergySummary? = nil) {
        self.weight = weight
        self.energy = energy
    }
}

/// Die Kacheln über dem Diagramm.
///
/// Eins zu eins die Registry aus der Weboberflaeche
/// (`weight-app/.../static/app.js`, `const WIDGETS`). Bewusst als Enum und
/// nicht als Tabelle von Closures: so ist jede Kachel an einer Stelle
/// vollstaendig beschrieben, und der Compiler merkt, wenn eine fehlt.
///
/// Die drei Energie-Kacheln stehen **hinter** `daysToTarget`, in allen drei
/// Registern gleich (Web, iOS, Android - Vertrag §5). Jedes wirft beim
/// Speichern unbekannte Schluessel weg: wer sie nur hier haette, verlöre sie
/// beim naechsten Speichern im Browser.
enum WeightWidget: String, CaseIterable, Identifiable, Sendable {
    case current, goal, diff, residual7, bmi
    case avg7, avg14, avg30, target, corridor, targetDate
    case startWeight, recordingStart, lastEntry, totalDiff
    case lost, remaining, progress, daysToTarget
    case deficit7, expenditure7, calibration

    var id: String { rawValue }

    /// Womit eine frische Installation anfaengt - **keine** Sonderstellung:
    /// diese vier lassen sich genauso entfernen wie alle anderen. Die Vorgabe
    /// liefert ohnehin der Server, wenn noch nie etwas gespeichert wurde; hier
    /// steht sie nur als Rueckfall, falls die Liste leer zurueckkommt, obwohl
    /// noch nie jemand etwas entfernt hat.
    static let defaults: [WeightWidget] = [.current, .goal, .diff, .bmi]

    /// Koerpergroesse fuer den BMI. Steht so auch in der Weboberflaeche
    /// (`HEIGHT_M`); eine weitere Personalisierung braucht diese App nicht.
    static let heightM = 1.94

    var label: String {
        switch self {
        case .current:        "Aktuell"
        case .goal:           "Ziel"
        case .diff:           "Differenz z. Target"
        case .residual7:      "7-Tage-Residuum"
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
        case .deficit7:       "Defizit ⌀ 7 T"
        case .expenditure7:   "Verbrauch ⌀ 7 T"
        case .calibration:    "Kalibrierung"
        }
    }

    func value(_ input: TileInput) -> String {
        let s = input.weight
        return switch self {
        case .current:        s.current.kg
        case .goal:           s.goalWeight.kg
        case .diff:
            if let current = s.current, let target = s.target {
                (current - target).signedKg
            } else { "–" }
        // Der Messwert jedes Tages gegen das Target desselben Tages, gemittelt
        // ueber die letzten sieben Tage - gerechnet im Dienst, siehe
        // `WeightSummary.residual7`. Bewusst nicht das zentrierte 7-Tage-Mittel
        // gegen das Target von heute: das hinkt am aktuellen Rand.
        case .residual7:      s.residual7.signedKg
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
        // Die Energie-Kacheln: Formate aus dem Vertrag (§5), gerechnet im
        // Dienst - siehe EnergyFormat.
        case .deficit7:       EnergyFormat.deficit7(input.energy)
        case .expenditure7:   EnergyFormat.expenditure7(input.energy)
        case .calibration:    EnergyFormat.calibration(input.energy)
        }
    }

    func tone(_ input: TileInput) -> Tone? {
        let s = input.weight
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
        case .residual7:
            guard let diff = s.residual7 else { return nil }
            // Beim Halten gilt die halbe Korridorbreite als Toleranz - dieselbe
            // Idee wie bei "Differenz z. Target": ein Wochenmittel innerhalb
            // des Bandes ist dort der Normalfall, kein Alarm.
            if s.corridorReachedOn != nil, let upper = s.corridorUpper, let goal = s.goalWeight,
               abs(diff) <= upper - goal {
                return .good
            }
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

    /// Eine Zeile Kleingedrucktes unter dem Wert - nur, wenn die Kachel etwas
    /// einzuschraenken hat. Das Wochen-Residuum sagt, wenn Tage fehlen: dann
    /// ist das Mittel schmaler, als ihr Name verspricht. Das Defizit sagt
    /// zusaetzlich, wenn es ein Ueberschuss ist; die Kalibrierung, auf wie
    /// vielen getrackten Tagen sie steht.
    func note(_ input: TileInput) -> String? {
        let s = input.weight
        switch self {
        case .residual7:
            guard s.residual7 != nil, let days = s.residual7Days, days < 7 else { return nil }
            return "\(days) von 7 Tagen"
        case .deficit7:
            return EnergyFormat.deficit7Note(input.energy)
        case .calibration:
            return EnergyFormat.calibrationNote(input.energy)
        default:
            return nil
        }
    }

    private static func bmi(_ s: WeightSummary) -> Double? {
        guard let current = s.current else { return nil }
        return current / (heightM * heightM)
    }
}
