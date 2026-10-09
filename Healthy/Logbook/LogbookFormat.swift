import Foundation

/// Die Effekte als Text - deutsch, mit „−" (U+2212), wie im Vertrag (§4.1, §5):
///
///     Name  +8,1 %-Pkt **
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
        pAdjusted.map(EvaluationStatistics.stars) ?? ""
    }

    /// Die Zeile mit Effekt und Sternen: „+8,1 %-Pkt **".
    static func effectLine(_ predictor: Predictor) -> String? {
        guard let effect = predictor.effect else { return nil }
        let stars = stars(predictor.pAdjusted)
        return stars.isEmpty ? self.effect(effect) : self.effect(effect) + " " + stars
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

    /// „2", „1,5", „0,25" - so viele Stellen wie noetig, deutsch.
    static func amount(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...2)))
    }

    /// Was in einem Mengenfeld steht, als Zahl - mit Komma wie auf der
    /// deutschen Tastatur, ein Punkt geht auch. `nil`, wenn es keine Menge
    /// ist, die der Dienst annimmt (mehr als 0, hoechstens 10.000).
    static func parseAmount(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0, value <= 10_000 else { return nil }
        return value
    }
}

/// Was auf der Logbook-Seite fuer einen Tag angetippt ist.
struct LogbookEntry: Equatable, Sendable {
    var isOn: Bool
    /// Nur mit Einheit - der Text im Mengenfeld.
    var amount: String
}

/// Vom gespeicherten Tag zur Eingabe und zurueck - neben der Seite, damit es
/// sich pruefen laesst.
enum LogbookDraft {

    /// Die Eingabe fuer einen Tag: gespeichert (oder wartend) wie es war, sonst
    /// alles aus.
    static func entries(for behaviors: [Behavior], values: [String: Double]?) -> [String: LogbookEntry] {
        var result: [String: LogbookEntry] = [:]
        for behavior in behaviors {
            let value = values?[behavior.id] ?? 0
            result[behavior.id] = LogbookEntry(
                isOn: value > 0,
                amount: behavior.unit != nil && value > 0 ? LogbookFormat.amount(value) : "")
        }
        return result
    }

    /// Was zum Dienst geht: nur, was angetippt ist - der Rest wird dort 0.
    /// Ohne Einheit 1, mit Einheit die Menge. `nil`, solange eine angetippte
    /// Verhaltensweise mit Einheit keine gueltige Menge hat: dann soll nicht
    /// gespeichert werden, statt eine erfundene Menge zu schicken.
    static func values(_ entries: [String: LogbookEntry], behaviors: [Behavior]) -> [String: Double]? {
        var values: [String: Double] = [:]
        for behavior in behaviors {
            guard let entry = entries[behavior.id], entry.isOn else { continue }
            if behavior.unit == nil {
                values[behavior.id] = 1
            } else {
                guard let amount = LogbookFormat.parseAmount(entry.amount) else { return nil }
                values[behavior.id] = amount
            }
        }
        return values
    }
}
