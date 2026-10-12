import Foundation

/// Was das Logbook im Dashboard zeigt, ohne Oberflaeche - damit es sich pruefen
/// laesst: welcher Wert in einer Zeile steht, ob ein Tag offen ist, welcher Tag
/// vorgewaehlt ist (Vertrag §4.2).
///
/// Eine Zeile zeigt, was gerade getippt wird, sonst was wartet, sonst den Stand
/// des Dienstes. Fehlt alles, ist sie **offen** - nicht „nein“.
enum LogbookDays {

    /// Der Wert einer Zeile; `nil` heisst offen.
    ///
    /// - Parameter typed: was gerade getippt wird und noch auf die Ruhe wartet,
    ///   je `LogbookChange.key` - `.some(nil)` heisst ausdruecklich offen.
    static func value(of behaviorId: String, on date: CalendarDate, overview: LogbookOverview?,
                      pending: [LogbookChange], typed: [String: Double?] = [:]) -> Double? {
        if let typedValue = typed[LogbookChange.key(date, behaviorId)] {
            return typedValue
        }
        if let last = pending.last(where: { $0.date == date && $0.behaviorId == behaviorId }) {
            return last.value
        }
        return overview?.day(date)?.values[behaviorId]
    }

    /// Ob an einem Tag eine aktive Verhaltensweise noch keinen Wert hat. Was
    /// wartet, gilt als beantwortet; ohne Verhaltensweise ist nichts offen.
    static func isOpen(_ date: CalendarDate, overview: LogbookOverview, pending: [LogbookChange]) -> Bool {
        overview.active.contains { value(of: $0.id, on: date, overview: overview, pending: pending) == nil }
    }

    /// Die Tage, an denen alles beantwortet ist - fuer die Erinnerung um 09:00.
    static func completeDays(_ overview: LogbookOverview, pending: [LogbookChange]) -> Set<CalendarDate> {
        guard !overview.active.isEmpty else { return [] }
        let candidates = Set(overview.days.map(\.date)).union(pending.map(\.date))
        return candidates.filter { !isOpen($0, overview: overview, pending: pending) }
    }

    /// Vorgewaehlt: gestern, solange gestern offen ist - sonst heute.
    static func preferredDay(today: CalendarDate, overview: LogbookOverview?, pending: [LogbookChange]) -> CalendarDate {
        let yesterday = today.adding(days: -1)
        guard let overview else { return yesterday }
        return isOpen(yesterday, overview: overview, pending: pending) ? yesterday : today
    }

    /// Bis zum Anfang der Nachtragsfrist zurueck, nie ueber heute hinaus.
    static func clamp(_ date: CalendarDate, today: CalendarDate, backfillDays: Int) -> CalendarDate {
        min(max(date, today.adding(days: -backfillDays)), today)
    }

    /// Ein Schritt am Zaehler: aus „offen“ gibt + eine 1 und − eine 0, sonst
    /// eins mehr oder weniger - nie unter 0 und nie ueber das, was der Dienst nimmt.
    static func stepped(_ value: Double?, by delta: Int) -> Double {
        guard let value else { return delta > 0 ? 1 : 0 }
        return min(max(value + Double(delta), 0), LogbookFormat.maxAmount)
    }

    /// Ja/Nein: ein Tipp auf die gewaehlte Antwort macht die Zeile wieder offen.
    static func answered(_ value: Double?, yes: Bool) -> Double? {
        let tapped: Double = yes ? 1 : 0
        return value == tapped ? nil : tapped
    }
}
