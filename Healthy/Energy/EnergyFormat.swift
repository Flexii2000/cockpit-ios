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

    /// Die Bilanz in zwei Teilen: „Defizit" und „≈ 460 kcal" bzw.
    /// „Überschuss" und „120 kcal" - das Wort nach dem gerundeten Wert (−0,3
    /// ist „Defizit 0 kcal"), der Betrag ohne Vorzeichen, das Wort sagt die
    /// Richtung. Nur an getrackten Tagen und heute, sonst gibt der Dienst
    /// keins. Getrennt, weil die Energie-Karte nur den Betrag einfaerbt.
    static func balance(_ day: EnergyDay) -> (word: String, amount: String, isSurplus: Bool)? {
        guard let deficit = day.deficitKcal else { return nil }
        let isSurplus = deficit.rounded() < 0
        return (isSurplus ? "Überschuss" : "Defizit", approx(day) + kcal(abs(deficit)), isSurplus)
    }

    /// „Defizit ≈ 460 kcal" bzw. „Überschuss ≈ 120 kcal".
    static func balanceLine(_ day: EnergyDay) -> String? {
        balance(day).map { $0.word + " " + $0.amount }
    }

    // MARK: - Energie-Karte im Dashboard

    /// „gegessen 2.150" unter dem Bilanzbalken. Heute ohne Eintrag 0 - genau
    /// so rechnet der Dienst die Prognose.
    static func eaten(_ day: EnergyDay) -> String {
        "gegessen " + GermanNumber.string(day.intakeKcal ?? 0)
    }

    /// „Verbrauch ≈ 2.840" unter dem Bilanzbalken - ohne Einheit, die steht
    /// gross darueber.
    static func expenditureShort(_ day: EnergyDay) -> String? {
        day.expenditureKcal.map { "Verbrauch " + approx(day) + GermanNumber.string($0) }
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
