import Foundation

/// Zahlen und Zeiten so, wie Felix sie sonst sieht: „45 %“, „Mo 12:00“, „in 1 h 31 min“.
enum ClaudeUsageFormat {

    static let locale = Locale(identifier: "de_DE")

    /// Ganze Prozent, mit schmalem Abstand wie in der CloudUsageBar („45 %“).
    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded())) %"
    }

    /// Die Zeile in der Menüleiste: nur die Woche (Felix, 02.11.: „nur die Wochensitzung“).
    static func menuBarTitle(_ usage: ClaudeUsage?) -> String {
        percent(usage?.weekly?.percent)
    }

    /// „Mo 12:00“ - innerhalb einer Woche reicht der Wochentag; heute nur die Uhrzeit.
    static func resetTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(Date.FormatStyle(locale: locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if calendar.isDate(date, inSameDayAs: now) { return "heute \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "morgen \(time)"
        }
        let weekday = date.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated))
            .replacingOccurrences(of: ".", with: "")
        if date.timeIntervalSince(now) < 6.5 * 86_400 { return "\(weekday) \(time)" }
        let day = date.formatted(Date.FormatStyle(locale: locale).day().month(.twoDigits))
        return "\(weekday) \(day) \(time)"
    }

    /// „in 1 h 31 min“, „in 3 T 4 h“, „in 12 min“.
    static func remaining(until date: Date, now: Date = Date()) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "jetzt" }
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let rest = minutes % 60
        if days > 0 { return hours > 0 ? "in \(days) T \(hours) h" : "in \(days) T" }
        if hours > 0 { return rest > 0 ? "in \(hours) h \(rest) min" : "in \(hours) h" }
        return "in \(rest) min"
    }

    /// „Tag 3 von 7“ - wie weit die Woche ist, passend zur Marke auf dem Balken.
    static func weekDay(_ usage: ClaudeUsage, now: Date = Date()) -> String? {
        guard let start = usage.weekStartedAt, let end = usage.weekly?.resetsAt, end > start else { return nil }
        let total = max(1, Int((end.timeIntervalSince(start) / 86_400).rounded()))
        let day = min(total, max(1, Int(now.timeIntervalSince(start) / 86_400) + 1))
        return "Tag \(day) von \(total)"
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// „12,30 $“ bzw. „12,30 €“ - für die Zusatznutzung.
    static func money(_ value: Double, currency: String) -> String {
        let symbol = currency == "USD" ? "$" : currency == "EUR" ? "€" : currency
        let number = value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        return "\(number) \(symbol)"
    }
}
