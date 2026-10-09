import Foundation

enum HealthEnergy {

    /// Was der Dienst je Tag annimmt (`EnergyController.check`). Liegt ein
    /// einziger Wert ausserhalb, lehnt er die **ganze** Anfrage mit 400 ab - ein
    /// falscher Wert einer Uhr blockierte sonst 30 Tage lang jeden Abgleich.
    static let activeRange = 0.0...10_000
    static let basalRange = 0.0...5_000

    /// Aktive Energie und Ruheenergie zu Tagen, in der Zeitzone des Geraets.
    ///
    /// Ein Tag mit nur einem der beiden Werte geht trotzdem raus - das fehlende
    /// Feld laesst beim Dienst den gespeicherten Wert stehen. Ein Tag ohne
    /// beide faellt weg: Health unterscheidet „nichts gemessen" nicht von
    /// „nichts verbraucht", also unterscheidet es der Bestand, indem der Tag
    /// fehlt (Vertrag §1.1). Ein unplausibler Wert zaehlt wie ein fehlender
    /// (wie auf Android).
    static func days(active: [DaySum], basal: [DaySum],
                     in timeZone: TimeZone = .current) -> [EnergyDayUpload] {
        var activeByDay: [CalendarDate: Double] = [:]
        var basalByDay: [CalendarDate: Double] = [:]
        for sum in active { activeByDay[CalendarDate(date: sum.dayStart, in: timeZone)] = sum.value }
        for sum in basal { basalByDay[CalendarDate(date: sum.dayStart, in: timeZone)] = sum.value }
        let dates = Set(activeByDay.keys).union(basalByDay.keys)
        return dates.sorted().compactMap { date in
            let active = activeByDay[date].map(round1).flatMap { activeRange.contains($0) ? $0 : nil }
            let basal = basalByDay[date].map(round1).flatMap { basalRange.contains($0) ? $0 : nil }
            guard active != nil || basal != nil else { return nil }
            return EnergyDayUpload(date: date, activeKcal: active, basalKcal: basal)
        }
    }

    /// Eine Nachkommastelle - genauer misst keine Uhr, und die Anfrage mit
    /// zehn Jahren Tagen bleibt klein.
    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

/// Zwei Kalendertage, beide einschliesslich.
struct DayRange: Equatable, Sendable {
    let from: CalendarDate
    let to: CalendarDate
}

/// Die einmalige Rueckholung der Historie in Bloecken: Energie bis 3.650 Tage,
/// Naechte bis 425 zurueck.
///
/// In Bloecken, weil zehn Jahre Tageskuebel oder gut ein Jahr Schlafsegmente samt
/// HRV in einem Zug den Speicher und die Geduld von iOS strapazieren; neueste
/// zuerst, weil die juengere Vergangenheit fuer Kalibrierung und Baseline
/// zaehlt. Wie weit es schon ging, merkt sich ein Cursor in den UserDefaults -
/// der aelteste erledigte Tag. Ein abgebrochener Lauf macht dort weiter.
enum HealthBackfill {

    /// Alle Bloecke von `newest` bis `oldest`, neueste zuerst, lueckenlos und
    /// ohne Ueberlappung. Der letzte ist kuerzer, wenn es nicht aufgeht.
    static func windows(newest: CalendarDate, oldest: CalendarDate, blockDays: Int) -> [DayRange] {
        guard blockDays > 0, oldest <= newest else { return [] }
        var result: [DayRange] = []
        var to = newest
        while to >= oldest {
            let candidate = to.adding(days: -(blockDays - 1))
            let from = candidate < oldest ? oldest : candidate
            result.append(DayRange(from: from, to: to))
            to = from.adding(days: -1)
        }
        return result
    }

    /// Der naechste Block nach dem Cursor; `nil`, wenn alles geholt ist.
    ///
    /// - Parameters:
    ///   - cursor: der aelteste schon geschickte Tag, `nil` vor dem ersten Block
    ///   - start: der juengste Tag der Rueckholung - der Tag vor dem Fenster,
    ///     das jeder Abgleich ohnehin liest
    ///   - oldest: wie weit es zurueckgeht
    static func next(after cursor: CalendarDate?, start: CalendarDate, oldest: CalendarDate,
                     blockDays: Int) -> DayRange? {
        let newest = cursor.map { $0.adding(days: -1) } ?? start
        return windows(newest: min(newest, start), oldest: oldest, blockDays: blockDays).first
    }
}
