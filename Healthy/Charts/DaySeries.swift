import Foundation

/// Ein Tageswert, wie ihn der Kalorienzaehler liefert.
struct DayValue: Sendable, Equatable {
    let date: CalendarDate
    let value: Double
}

/// Ein zusammenhaengendes Stueck einer Tageskurve.
struct ChartRun: Identifiable, Sendable, Equatable {
    let id: String
    let samples: [ChartSample]

    /// Ein einzelner Tag zwischen zwei Luecken. Als Linie waere er unsichtbar
    /// - er braucht einen Punkt.
    var isSingle: Bool { samples.count == 1 }
}

enum DaySeries {

    /// Zerlegt Tageswerte in Laeufe aufeinanderfolgender Tage.
    ///
    /// Der Kalorienzaehler liefert **nur Tage mit Eintraegen**
    /// (`dailyTotals` in FoodService); fehlende Tage sind unbekannt, nicht
    /// null. Eine durchgezogene Linie darueber hinweg wuerde behaupten,
    /// dazwischen sei etwas gemessen worden - deshalb wird an jeder Luecke
    /// getrennt. Dieselbe Entscheidung wie `spanGaps: false` im Web.
    static func runs(_ values: [DayValue], key: String,
                     in timeZone: TimeZone = .current) -> [ChartRun] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var result: [ChartRun] = []
        var current: [ChartSample] = []
        var previous: CalendarDate?

        func flush() {
            guard !current.isEmpty else { return }
            result.append(ChartRun(id: "\(key)-\(result.count)", samples: current))
            current = []
        }

        for entry in values.sorted(by: { $0.date < $1.date }) {
            if let previous {
                let gap = calendar.dateComponents([.day],
                                                  from: previous.startOfDay(in: timeZone),
                                                  to: entry.date.startOfDay(in: timeZone)).day ?? 0
                // Ueber Sommerzeitwechsel ist ein Tag nicht 86400 Sekunden -
                // deshalb ueber den Kalender zaehlen und nicht rechnen.
                if gap != 1 { flush() }
            }
            current.append(ChartSample(date: entry.date.startOfDay(in: timeZone),
                                       value: entry.value))
            previous = entry.date
        }
        flush()
        return result
    }
}

/// Ein Stueck der Mittelwertkurve. Getrennt an Luecken und dort, wo das
/// Mittelungsfenster unvollstaendig wird - der vorlaeufige Rand wird
/// gepunktet gezeichnet, wie beim Gewichtsmittel.
struct AverageRun: Identifiable, Sendable, Equatable {
    let id: String
    let complete: Bool
    let samples: [ChartSample]

    var isSingle: Bool { samples.count == 1 }
}

extension DaySeries {

    /// Wie `runs`, fuer das gleitende Mittel aus dem Kalorienzaehler: ein
    /// Lauf endet an einer Luecke (sieben Tage ohne Eintrag am Stueck) und
    /// dort, wo `complete` umschlaegt. Beim Umschlag wandert der letzte Punkt
    /// mit in den naechsten Lauf, damit die gepunktete Linie an der
    /// durchgezogenen ansetzt statt daneben zu beginnen.
    /// - Parameter map: rechnet den kcal-Wert auf eine andere Skala um (der
    ///   Gewicht-Tab zeichnet die kcal in den Gewichtsbereich hinein).
    static func averageRuns(_ values: [DayAverage], key: String,
                            map: (Double) -> Double = { $0 },
                            in timeZone: TimeZone = .current) -> [AverageRun] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var result: [AverageRun] = []
        var current: [ChartSample] = []
        var currentComplete = true
        var previous: DayAverage?

        func flush() {
            guard !current.isEmpty else { return }
            result.append(AverageRun(id: "\(key)-\(result.count)", complete: currentComplete,
                                     samples: current))
            current = []
        }

        for entry in values.sorted(by: { $0.date < $1.date }) {
            if let previous {
                let gap = calendar.dateComponents([.day],
                                                  from: previous.date.startOfDay(in: timeZone),
                                                  to: entry.date.startOfDay(in: timeZone)).day ?? 0
                if gap != 1 {
                    flush()
                    currentComplete = entry.complete
                } else if entry.complete != currentComplete {
                    let last = current.last
                    flush()
                    currentComplete = entry.complete
                    if let last { current.append(last) }
                }
            } else {
                currentComplete = entry.complete
            }
            current.append(ChartSample(date: entry.date.startOfDay(in: timeZone),
                                       value: map(entry.kcal)))
            previous = entry
        }
        flush()
        return result
    }
}
