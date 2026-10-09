import Foundation

/// Ein Tag des Normalbands: von–bis in Millisekunden.
struct HrvBandSample: Identifiable, Equatable, Sendable {
    let date: Date
    let low: Double
    let high: Double
    var id: Date { date }
}

/// Ein zusammenhaengendes Stueck des Normalbands.
struct HrvBandRun: Identifiable, Equatable, Sendable {
    let id: String
    let samples: [HrvBandSample]
}

/// Aufbereitung der HRV-Kurve auf der Recovery-Seite - wie `WeightChartData`
/// neben der View, damit sie sich pruefen laesst.
enum RecoveryChartData {

    /// Die HRV je Nacht. Naechte ohne HRV fehlen - unbekannt, nicht null.
    static func hrvValues(_ days: [RecoveryDay]) -> [DayValue] {
        days.compactMap { day in
            day.component(.hrv).map { DayValue(date: day.date, value: $0.value) }
        }
    }

    /// Die Linie, an jeder Luecke getrennt: eine Nacht ohne Uhr ist
    /// unbekannt, und eine Linie darueber behauptete einen Verlauf.
    static func hrvRuns(_ days: [RecoveryDay], in timeZone: TimeZone = .current) -> [ChartRun] {
        DaySeries.runs(hrvValues(days), key: "hrv", in: timeZone)
    }

    /// Das Normalband - Median ± 0,5 Streuung der 60 Naechte davor, je Tag
    /// vom Dienst mitgeliefert (`hrvTrend`). Nur Tage mit Score haben eins; an
    /// den Luecken dazwischen reisst es ab, wie die Linie.
    static func bandRuns(_ days: [RecoveryDay], in timeZone: TimeZone = .current) -> [HrvBandRun] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var result: [HrvBandRun] = []
        var current: [HrvBandSample] = []
        var previous: CalendarDate?

        func flush() {
            guard !current.isEmpty else { return }
            result.append(HrvBandRun(id: "band-\(result.count)", samples: current))
            current = []
        }

        for day in days.sorted(by: { $0.date < $1.date }) {
            guard let low = day.hrvTrend?.normalLowMs, let high = day.hrvTrend?.normalHighMs else { continue }
            if let previous,
               calendar.dateComponents([.day], from: previous.startOfDay(in: timeZone),
                                       to: day.date.startOfDay(in: timeZone)).day != 1 {
                flush()
            }
            current.append(HrvBandSample(date: day.date.startOfDay(in: timeZone), low: low, high: high))
            previous = day.date
        }
        flush()
        return result
    }

    /// Der Bereich der y-Achse: Linie und Band ganz im Bild, mit etwas Luft.
    /// Nicht bei null beginnend - HRV schwankt um ein paar Millisekunden, und
    /// genau die sollen zu sehen sein.
    static func domain(_ days: [RecoveryDay]) -> ClosedRange<Double> {
        let values = hrvValues(days).map(\.value)
            + days.compactMap(\.hrvTrend?.normalLowMs) + days.compactMap(\.hrvTrend?.normalHighMs)
        guard let low = values.min(), let high = values.max() else { return 20...80 }
        let padding = max((high - low) * 0.1, 3)
        return max(0, low - padding)...(high + padding)
    }
}
