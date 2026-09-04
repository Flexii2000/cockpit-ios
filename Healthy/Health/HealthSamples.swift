import Foundation

/// Ein Gewichtswert aus Health, auf das Noetige eingedampft.
///
/// Eigener Typ statt `HKQuantitySample`: der ist nicht `Sendable` und darf
/// deshalb nicht aus dem Abfrage-Rueckruf herausgereicht werden. Nebenbei
/// laesst sich die Auswahl so ohne HealthKit testen.
struct WeightSample: Sendable, Equatable {
    let takenAt: Date
    let kilograms: Double
}

enum HealthSamples {

    /// Ein Wert je Kalendertag - **die frueheste Messung des Tages**.
    ///
    /// Health kennt beliebig viele Messungen pro Tag, der Weight Tracker
    /// genau eine. Genommen wird die frueheste, weil das in aller Regel die
    /// morgens nuechtern gewogene ist: der Wert, der ueber Tage hinweg
    /// vergleichbar bleibt. Eine Abendmessung nach dem Essen liegt regelmaessig
    /// ein bis zwei Kilo darueber und wuerde die Kurve verrauschen.
    static func dailyValues(_ samples: [WeightSample],
                            in timeZone: TimeZone = .current) -> [DayValue] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var earliest: [CalendarDate: WeightSample] = [:]
        for sample in samples {
            let parts = calendar.dateComponents([.year, .month, .day], from: sample.takenAt)
            guard let year = parts.year, let month = parts.month, let day = parts.day
            else { continue }
            let key = CalendarDate(year: year, month: month, day: day)
            if let existing = earliest[key], existing.takenAt <= sample.takenAt { continue }
            earliest[key] = sample
        }
        return earliest
            .map { DayValue(date: $0.key, value: $0.value.kilograms) }
            .sorted { $0.date < $1.date }
    }
}
