import Foundation

/// Ein Tageskuebel aus einer Statistik-Abfrage, auf das Noetige eingedampft.
///
/// Eigener Typ statt `HKStatistics`: der ist nicht `Sendable` und darf den
/// Abfrage-Rueckruf nicht verlassen. Nebenbei laesst sich die Zuordnung so
/// ohne HealthKit pruefen.
struct StepBucket: Sendable, Equatable {
    let dayStart: Date
    let count: Double
}

/// Die Schrittzahl eines Tages, wie sie zum Server geht.
struct StepDay: Codable, Equatable, Sendable {
    let date: CalendarDate
    let steps: Int
}

enum HealthSteps {

    /// Kuebel zu Kalendertagen, in der Zeitzone des Geraets.
    ///
    /// Kuebel ohne Messung sind vorher schon herausgefallen (`sumQuantity()`
    /// lieferte `nil`). Was hier mit 0 ankaeme, waere kein Wissen, sondern
    /// eine Null - und die gehoert nicht in den Bestand: Health unterscheidet
    /// "nichts gemessen" nicht von "null Schritte", also unterscheiden wir es,
    /// indem der Tag fehlt.
    static func dailyValues(_ buckets: [StepBucket],
                            in timeZone: TimeZone = .current) -> [StepDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return buckets.compactMap { bucket in
            guard bucket.count > 0 else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: bucket.dayStart)
            guard let year = parts.year, let month = parts.month, let day = parts.day
            else { return nil }
            return StepDay(date: CalendarDate(year: year, month: month, day: day),
                           steps: Int(bucket.count.rounded()))
        }
    }
}
