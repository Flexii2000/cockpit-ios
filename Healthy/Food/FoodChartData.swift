import Foundation

/// Aufbereitung des Verlaufsdiagramms.
///
/// Wie `WeightChartData` bewusst neben der View: hier steckt die Rechnerei,
/// an der drei Fehler auf einmal hingen (doppelte Achsenbeschriftung,
/// wirkungsloser Zeitraum-Umschalter, verschwundene Gewichtskurve). Alle drei
/// hatten dieselbe Ursache - der Zeitbereich wurde aus den *vorhandenen
/// Daten* abgeleitet statt aus dem *gewaehlten Zeitraum*.
enum FoodChartData {

    /// Nullpunkt der kcal-Achse. Nicht 0: ein Tag liegt praktisch nie unter
    /// ~1000 kcal, und eine bei null beginnende Achse presst den
    /// interessanten Bereich in ein paar Pixel zusammen.
    static let kcalBase: Double = 1500

    static func kcalRuns(_ history: [DayTotal]) -> [ChartRun] {
        DaySeries.runs(history.map { DayValue(date: $0.date, value: $0.consumed.kcal) },
                       key: "kcal")
    }

    static func daysOverTarget(_ history: [DayTotal], target: Double?,
                               tolerance: Double) -> [DayValue] {
        guard let target else { return [] }
        return history
            .filter { $0.consumed.kcal > target + tolerance }
            .map { DayValue(date: $0.date, value: $0.consumed.kcal) }
    }

    /// Die Gewichtswerte **im gewaehlten Fenster**.
    ///
    /// Frueher wurde auf den ersten Tag mit kcal-Eintrag zugeschnitten. Mit
    /// zwei erfassten Tagen blieben davon zwei Punkte uebrig, und die
    /// Gewichtskurve war praktisch weg - obwohl fuer den Zeitraum 90 Werte
    /// vorlagen. Zugeschnitten wird auf den Zeitraum, nicht auf die Datenlage
    /// des anderen Dienstes.
    /// - Parameter series: `.avg7` fuer die geglaettete Kurve, `.measured`
    ///   fuer die tatsaechlich gewogenen Tageswerte. Beides ist einzeln
    ///   zuschaltbar, weil es zwei verschiedene Fragen beantwortet: der
    ///   Trend und was an einem bestimmten Tag auf der Waage stand.
    static func weightValues(_ points: [WeightPoint], series: WeightSeries,
                             from: CalendarDate, to: CalendarDate) -> [DayValue] {
        points.compactMap { point in
            guard point.date >= from, point.date <= to else { return nil }
            let raw: Double? = switch series {
            case .measured: point.measured
            case .avg7:     point.avg7
            case .avg14:    point.avg14
            case .avg30:    point.avg30
            case .target:   point.target
            case .kcal:     nil
            }
            return raw.map { DayValue(date: point.date, value: $0) }
        }
    }

    static func kcalDomain(_ history: [DayTotal], target: Double?) -> ClosedRange<Double> {
        let values = history.map(\.consumed.kcal) + [target].compactMap { $0 }
        let lower = min(kcalBase, (values.min() ?? kcalBase) - 100)
        let upper = max((values.max() ?? 2500) + 150, (target ?? 2000) * 1.1)
        return lower...max(upper, lower + 100)
    }

    /// Der Gewichtsbereich mit etwas Luft - sonst klebt die Kurve am Rand.
    static func weightRange(_ values: [DayValue]) -> ClosedRange<Double>? {
        let numbers = values.map(\.value)
        guard let low = numbers.min(), let high = numbers.max() else { return nil }
        let padding = max((high - low) * 0.3, 0.5)
        return (low - padding)...(high + padding)
    }

    /// Rechnet einen Wert von einer Skala auf die andere um. Swift Charts
    /// kennt nur **eine** y-Skala; die Gewichtskurve wird deshalb in den
    /// kcal-Bereich hineingerechnet und rechts eigens beschriftet.
    static func scale(_ value: Double,
                      from source: ClosedRange<Double>,
                      to target: ClosedRange<Double>) -> Double {
        guard source.upperBound > source.lowerBound else { return target.lowerBound }
        let share = (value - source.lowerBound) / (source.upperBound - source.lowerBound)
        return target.lowerBound + share * (target.upperBound - target.lowerBound)
    }
}
