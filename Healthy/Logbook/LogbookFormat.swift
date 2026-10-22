import Foundation

/// Die Effekte als Text - deutsch, mit „−" (U+2212), wie im Vertrag (§4.1, §5):
///
///     Name  +8,1 %-Pkt **
///     HRV +9 % · RHF −1,9 bpm
///     [+3,2; +13,0] · 41 ja · 37 nein
enum LogbookFormat {

    /// „+8,1 %-Pkt" - Prozentpunkte Recovery am naechsten Morgen.
    static func effect(_ value: Double) -> String {
        GermanNumber.string(value, decimals: 1, signed: true) + " %-Pkt"
    }

    /// „[+3,2; +13,0]" - das 95-%-Intervall.
    static func interval(_ low: Double, _ high: Double) -> String {
        "[" + GermanNumber.string(low, decimals: 1, signed: true) + "; "
            + GermanNumber.string(high, decimals: 1, signed: true) + "]"
    }

    /// Nach dem Holm-korrigierten p: < 0,001 `***`, < 0,01 `**`, < 0,05 `*`.
    static func stars(_ pAdjusted: Double?) -> String {
        pAdjusted.map(Significance.stars) ?? ""
    }

    /// Die Zeile mit Effekt und Sternen: „+8,1 %-Pkt **".
    static func effectLine(_ predictor: Predictor) -> String? {
        guard let effect = predictor.effect else { return nil }
        let stars = stars(predictor.pAdjusted)
        return stars.isEmpty ? self.effect(effect) : self.effect(effect) + " " + stars
    }

    /// Die Bausteine unter dem Effekt: „HRV +9 % · RHF −1,9 bpm" - HRV ganz,
    /// der Puls mit einer Stelle, beide mit Vorzeichen; was auf null rundet,
    /// steht ohne („HRV 0 %"). Fehlt einer, steht der andere allein; fehlen
    /// beide, gibt es die Zeile nicht (Vertrag §4.2).
    static func components(_ predictor: Predictor) -> String? {
        var parts: [String] = []
        if let hrv = predictor.hrvEffectPercent {
            parts.append("HRV " + GermanNumber.string(hrv, signed: true) + " %")
        }
        if let heart = predictor.sleepingHeartRateEffectBpm {
            parts.append("RHF " + GermanNumber.string(heart, decimals: 1, signed: true) + " bpm")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// „je 1.000 Schritte", „je Stück" - wofuer der Effekt einer Menge gilt.
    /// Ja/nein hat keinen.
    static func perUnit(_ predictor: Predictor) -> String? {
        guard predictor.kind == .amount, let label = predictor.unitLabel, !label.isEmpty else { return nil }
        return predictor.perUnit == 1 ? "je " + label : "je " + GermanNumber.string(predictor.perUnit) + " " + label
    }

    /// Die Zeile darunter: „[+3,2; +13,0] · 41 ja · 37 nein", bei Mengen
    /// „[+0,2; +2,4] · 78 Tage".
    static func detail(_ predictor: Predictor) -> String {
        var parts: [String] = []
        if let low = predictor.ciLow, let high = predictor.ciHigh {
            parts.append(interval(low, high))
        }
        if predictor.kind == .binary, let yes = predictor.nYes, let no = predictor.nNo {
            parts.append("\(yes) ja")
            parts.append("\(no) nein")
        } else {
            parts.append(predictor.n == 1 ? "1 Tag" : "\(predictor.n) Tage")
        }
        return parts.joined(separator: " · ")
    }

    /// Wie weit eine Zeile ohne Effekt noch ist: „3/5 ja · 5/5 nein" -
    /// je fuenfmal ja und nein braucht der Dienst, dazu 14 Tage; eine Menge
    /// 14 Tage, die Dosis zehn Ja-Tage.
    static func notEvaluated(_ predictor: Predictor) -> String {
        if predictor.status == .notSeparable {
            return "fällt aufs Wochenende"
        }
        if predictor.kind == .binary {
            let yes = predictor.nYes ?? 0, no = predictor.nNo ?? 0
            var parts = ["\(min(yes, 5))/5 ja", "\(min(no, 5))/5 nein"]
            if yes >= 5, no >= 5, predictor.n < 14 { parts.append("\(predictor.n)/14 Tage") }
            return parts.joined(separator: " · ")
        }
        if predictor.variant == .dose {
            return predictor.n < 10 ? "\(predictor.n)/10 Ja-Tage" : "\(predictor.n) Ja-Tage"
        }
        return predictor.n < 14 ? "\(predictor.n)/14 Tage" : "\(predictor.n) Tage"
    }

    // MARK: - Mengen

    /// Mehr nimmt der Dienst nicht.
    static let maxAmount: Double = 10_000

    /// „2", „1,5", „0,25" - so viele Stellen wie noetig, deutsch.
    static func amount(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...2)))
    }

    /// Was in der Eingabe einer Menge steht, als Zahl - mit Komma wie auf der
    /// deutschen Tastatur, ein Punkt geht auch. 0 ist eine Antwort („heute
    /// keine“), offen ist etwas anderes. `nil`, wenn der Dienst es nicht nimmt.
    static func parseAmount(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value >= 0, value <= maxAmount else { return nil }
        return value
    }
}
