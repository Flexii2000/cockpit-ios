import Foundation

/// Ein Kalendertag - Jahr, Monat, Tag, sonst nichts.
///
/// Warum kein `Date`: Spring liefert `LocalDate` als `"2026-09-01"`, und das
/// ist ein Tag im Kalender, kein Zeitpunkt. Wandelt man das in ein `Date`,
/// haengt am Ergebnis eine Zeitzone, und der 1. September wird beim Anzeigen
/// je nach Geraeteeinstellung zum 31. August. Genau diese Klasse von Fehlern
/// faellt weg, wenn der Tag ein Tag bleibt.
struct CalendarDate: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Der Kalendertag, in den ein Zeitpunkt faellt - in der Zone des Geraets.
    init(date: Date, in timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func today(in timeZone: TimeZone = .current) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return CalendarDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Fuer Diagramme: der Tagesbeginn in der angegebenen Zeitzone. Nur hier
    /// wird aus dem Tag ein Zeitpunkt - bewusst an einer einzigen Stelle.
    func startOfDay(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = CalendarDate(iso: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Kein Datum im Format yyyy-MM-dd: \(raw)"))
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}
