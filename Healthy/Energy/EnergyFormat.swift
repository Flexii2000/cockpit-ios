import Foundation

/// Zahlen wie im Vertrag (§5): deutsch mit Tausenderpunkt und Komma, negative
/// mit „−" (U+2212) - unabhaengig von der Sprache des Geraets.
///
/// `Double.whole` richtet sich nach der Geraetesprache; auf einem englisch
/// eingestellten iPhone stuende dort „2,610" fuer zweitausend. Fuer die neuen
/// Zeilen, die auf allen Oberflaechen gleich aussehen sollen, taugt das nicht.
enum GermanNumber {

    static let minus = "\u{2212}"

    /// - Parameter signed: „+" vor positiven Werten; null bleibt ohne Zeichen.
    static func string(_ value: Double, decimals: Int = 0, signed: Bool = false) -> String {
        let factor = pow(10, Double(decimals))
        var rounded = (value * factor).rounded() / factor
        // Keine „−0": was auf null rundet, ist null.
        if rounded == 0 { rounded = 0 }
        let style = FloatingPointFormatStyle<Double>.number
            .locale(Locale(identifier: "de_DE"))
            .precision(.fractionLength(decimals))
            .sign(strategy: signed ? .always(includingZero: false) : .automatic)
        return rounded.formatted(style).replacingOccurrences(of: "-", with: minus)
    }
}

/// Die Energiebilanz als Text - die Formate aus dem Vertrag (§5), fuer alle
/// Oberflaechen gleich: Essen-Tab, Kacheln im Gewicht-Tab, Dashboard.
enum EnergyFormat {

    /// „2.610 kcal"; ein Ueberschuss als „−120 kcal".
    static func kcal(_ value: Double) -> String {
        GermanNumber.string(value) + " kcal"
    }

    /// Die Korrektur der Uhr: Faktor − 1 in ganzen Prozent - „−8 %", „+3 %",
    /// „0 %". Passt zur Energiezeile, in der dieselbe Zahl steht.
    static func calibration(_ factor: Double) -> String {
        GermanNumber.string((factor - 1) * 100, signed: true) + " %"
    }

    /// „≈ " vor allem, was eine Prognose ist (heute).
    private static func approx(_ day: EnergyDay) -> String {
        day.projected ? "≈ " : ""
    }

    // MARK: - Energiezeilen im Essen-Tab

    /// „Verbrauch ≈ 2.610 kcal"
    static func expenditure(_ day: EnergyDay) -> String? {
        day.expenditureKcal.map { "Verbrauch " + approx(day) + kcal($0) }
    }

    /// „Uhr 2.840 · −8 %" - nur, wenn die Uhr etwas gemeldet hat und ihr
    /// Wert korrigiert wurde. Sonst stuende dieselbe Zahl zweimal da.
    static func watch(_ day: EnergyDay) -> String? {
        guard let watch = day.watchKcal, day.factor != 1 else { return nil }
        return "Uhr " + GermanNumber.string(watch) + " · " + calibration(day.factor)
    }

    /// „Verbrauch ≈ 2.610 kcal · Uhr 2.840 · −8 %"
    static func expenditureLine(_ day: EnergyDay) -> String? {
        guard let expenditure = expenditure(day) else { return nil }
        return [expenditure, watch(day)].compactMap { $0 }.joined(separator: " · ")
    }

    /// „Defizit ≈ 460 kcal" bzw. „Überschuss ≈ 120 kcal" - nur an getrackten
    /// Tagen und heute, sonst gibt der Dienst keins.
    static func balanceLine(_ day: EnergyDay) -> String? {
        guard let deficit = day.deficitKcal else { return nil }
        let word = deficit.rounded() < 0 ? "Überschuss" : "Defizit"
        return word + " " + approx(day) + kcal(abs(deficit))
    }

    // MARK: - Dashboard

    /// Die Energie-Karte: „Verbrauch ≈ 2.840", „gegessen 2.150", „Defizit ≈
    /// 690 kcal" - die Einheit einmal am Ende. Ohne Kalorienzaehler nur der
    /// Verbrauch: das Gegessene ist dann unbekannt, nicht 0.
    static func dashboardParts(_ day: EnergyDay, foodAvailable: Bool) -> [String] {
        var parts: [String] = []
        if let expenditure = day.expenditureKcal {
            parts.append("Verbrauch " + approx(day) + GermanNumber.string(expenditure))
        }
        if foodAvailable {
            // Heute ohne Eintrag ist das Gegessene bisher null - genau so
            // rechnet der Dienst die Prognose.
            if let intake = day.intakeKcal ?? (day.projected ? 0 : nil) {
                parts.append("gegessen " + GermanNumber.string(intake))
            }
            if let deficit = day.deficitKcal {
                let word = deficit.rounded() < 0 ? "Überschuss" : "Defizit"
                parts.append(word + " " + approx(day) + GermanNumber.string(abs(deficit)))
            }
        }
        if let last = parts.popLast() { parts.append(last + " kcal") }
        return parts
    }

    // MARK: - Kacheln im Gewicht-Tab

    /// „Defizit ⌀ 7 T": „460 kcal", ein Ueberschuss als „−120 kcal".
    static func deficit7(_ summary: EnergySummary?) -> String {
        summary?.deficit7.map(kcal) ?? "–"
    }

    /// „Überschuss", wenn es einer ist; „5 von 7 Tagen", wenn Tage fehlen.
    static func deficit7Note(_ summary: EnergySummary?) -> String? {
        guard let summary, let deficit = summary.deficit7 else { return nil }
        var parts: [String] = []
        if deficit.rounded() < 0 { parts.append("Überschuss") }
        if summary.deficit7Days < 7 { parts.append("\(summary.deficit7Days) von 7 Tagen") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// „Verbrauch ⌀ 7 T": „2.610 kcal".
    static func expenditure7(_ summary: EnergySummary?) -> String {
        summary?.expenditure7.map(kcal) ?? "–"
    }

    /// „Kalibrierung": „−8 %".
    static func calibration(_ summary: EnergySummary?) -> String {
        summary.map { calibration($0.calibration.factor) } ?? "–"
    }

    /// „25 Tage" - die getrackten Tage im Fenster der Kalibrierung.
    static func calibrationNote(_ summary: EnergySummary?) -> String? {
        guard let days = summary?.calibration.trackedDays else { return nil }
        return days == 1 ? "1 Tag" : "\(days) Tage"
    }
}
