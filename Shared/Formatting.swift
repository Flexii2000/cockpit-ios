import Foundation

extension Double {
    /// "82,4 kg" - eine Nachkommastelle, wie in der Weboberflaeche.
    var kg: String { String(format: "%.1f kg", self) }

    /// Mit Vorzeichen, damit eine Zunahme auch als solche zu erkennen ist.
    var signedKg: String { String(format: "%@%.1f kg", self >= 0 ? "+" : "", self) }
}

extension Optional where Wrapped == Double {
    var kg: String { self?.kg ?? "–" }
    var signedKg: String { self?.signedKg ?? "–" }
}

extension CalendarDate {
    /// "01.09.26" - kurz genug fuer eine Kachel.
    var short: String {
        String(format: "%02d.%02d.%02d", day, month, year % 100)
    }

    /// Tage von heute bis zu diesem Datum; negativ, wenn er vorbei ist.
    func daysFromToday() -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let from = CalendarDate.today().startOfDay()
        let to = startOfDay()
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

extension Optional where Wrapped == CalendarDate {
    var short: String { self?.short ?? "–" }
}

extension Double {
    /// Ganze Zahl in deutscher Schreibweise ("1.234").
    var whole: String { formatted(.number.precision(.fractionLength(0))) }

    /// Eine Nachkommastelle, ohne Einheit.
    var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
}
