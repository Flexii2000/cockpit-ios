import Charts
import SwiftUI

struct WeightChartView: View {

    let points: [WeightPoint]
    let vacations: [Vacation]
    let corridor: (lower: Double, upper: Double)?
    let kcalByDay: [DayValue]
    let kcalTarget: Double?
    let visible: Set<WeightSeries>

    var body: some View {
        Chart {
            // Urlaube ganz nach hinten: sie sind Hintergrund, keine Serie.
            ForEach(clampedVacations) { band in
                RectangleMark(
                    xStart: .value("von", band.start),
                    xEnd: .value("bis", band.end))
                .foregroundStyle(Palette.vacation.opacity(0.16))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    if let label = band.label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 3)
                    }
                }
            }

            // Zielkorridor - nur wenn er schon gilt.
            if let corridor {
                RectangleMark(
                    yStart: .value("unten", corridor.lower),
                    yEnd: .value("oben", corridor.upper))
                .foregroundStyle(Palette.target.opacity(0.12))
            }

            if visible.contains(.kcal) {
                // Zuerst gezeichnet und damit hinter den Gewichtskurven: die
                // kcal sind Kontext, nicht die Hauptsache.
                if let kcalTarget {
                    RuleMark(y: .value("kcal-Ziel", toWeightScale(kcalTarget)))
                        .foregroundStyle(Palette.kcal.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(kcalRuns) { run in
                    if run.isSingle, let only = run.samples.first {
                        // Ein Tag zwischen zwei Luecken hat kein Liniensegment
                        // und waere sonst unsichtbar.
                        PointMark(x: .value("Tag", only.date),
                                  y: .value("kcal", only.value))
                        .foregroundStyle(Palette.kcal)
                        .symbolSize(14)
                    } else {
                        ForEach(run.samples) { sample in
                            LineMark(x: .value("Tag", sample.date),
                                     y: .value("kcal", sample.value),
                                     series: .value("Serie", run.id))
                        }
                        .foregroundStyle(Palette.kcal)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }

            if visible.contains(.measured) {
                ForEach(samples(\.measured)) { sample in
                    LineMark(x: .value("Tag", sample.date),
                             y: .value("kg", sample.value),
                             series: .value("Serie", "measured"))
                }
                .foregroundStyle(Palette.measured)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
                .interpolationMethod(.catmullRom)
            }

            ForEach(averageSegments) { segment in
                ForEach(segment.samples) { sample in
                    LineMark(x: .value("Tag", sample.date),
                             y: .value("kg", sample.value),
                             series: .value("Serie", segment.id))
                }
                .foregroundStyle(segment.series.color)
                // Gepunktet, wo das Mittelungsfenster noch nicht voll besetzt
                // ist - am aktuellen Rand ist es das nie.
                .lineStyle(StrokeStyle(lineWidth: 2.2,
                                       dash: segment.complete ? [] : [1, 5]))
                .interpolationMethod(.catmullRom)
            }

            if visible.contains(.target) {
                ForEach(samples(\.target)) { sample in
                    LineMark(x: .value("Tag", sample.date),
                             y: .value("kg", sample.value),
                             series: .value("Serie", "target"))
                }
                .foregroundStyle(Palette.target)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        // Ohne festen Bereich zieht Swift Charts die Achse bis 0 herunter -
        // die Kurve saesse dann als flacher Strich im obersten Zehntel. Sie
        // schwankt um ein paar Kilogramm, und genau die sollen zu sehen sein.
        .chartYScale(domain: yDomain)
        .chartXAxis {
            // `.aligned` haelt die aeusseren Beschriftungen im Bild - ohne das
            // wird die letzte am rechten Rand abgeschnitten ("1....").
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.day().month(.abbreviated))
                    }
                }
            }
        }
        .chartYAxis {
            // Kilogramm links, kcal rechts. Zwei Skalen kennt Swift Charts
            // nicht - die kcal sind in den Gewichtsbereich hineingerechnet,
            // und diese Achse sagt, welche Werte dahinterstehen.
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                if let weight = value.as(Double.self) {
                    AxisValueLabel {
                        Text(String(format: "%.0f", weight)).font(.caption2)
                    }
                }
            }
            if visible.contains(.kcal) {
                AxisMarks(position: .trailing, values: kcalTicks.map(toWeightScale)) { value in
                    if let mapped = value.as(Double.self),
                       let kcal = fromWeightScale(mapped) {
                        AxisValueLabel {
                            Text(kcal.whole)
                                .font(.caption2)
                                .foregroundStyle(Palette.kcal)
                        }
                    }
                }
            }
        }
        .frame(height: 260)
    }

    // MARK: - kcal auf der Gewichtsskala

    /// Nullpunkt der kcal-Skala. Nicht 0: ein Tag liegt praktisch nie unter
    /// ~1000 kcal, und eine bei null beginnende Skala presst den
    /// interessanten Bereich in ein paar Pixel zusammen.
    private static let kcalBase: Double = 1500

    private var kcalDomain: ClosedRange<Double> {
        let values = kcalByDay.map(\.value) + [kcalTarget].compactMap { $0 }
        let lower = min(Self.kcalBase, (values.min() ?? Self.kcalBase) - 100)
        let upper = max((values.max() ?? 2500) + 100, (kcalTarget ?? 2000) * 1.05)
        return lower...max(upper, lower + 100)
    }

    private var kcalRuns: [ChartRun] {
        let mapped = kcalByDay.map { DayValue(date: $0.date, value: toWeightScale($0.value)) }
        return DaySeries.runs(mapped, key: "kcal")
    }

    private var kcalTicks: [Double] {
        let low = kcalDomain.lowerBound, high = kcalDomain.upperBound
        return [low + (high - low) * 0.25,
                low + (high - low) * 0.6,
                low + (high - low) * 0.95]
    }

    private func toWeightScale(_ kcal: Double) -> Double {
        let domain = kcalDomain
        guard domain.upperBound > domain.lowerBound else { return yDomain.lowerBound }
        let share = (kcal - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return yDomain.lowerBound + share * (yDomain.upperBound - yDomain.lowerBound)
    }

    private func fromWeightScale(_ value: Double) -> Double? {
        let domain = kcalDomain
        guard yDomain.upperBound > yDomain.lowerBound else { return nil }
        let share = (value - yDomain.lowerBound) / (yDomain.upperBound - yDomain.lowerBound)
        return domain.lowerBound + share * (domain.upperBound - domain.lowerBound)
    }

    /// Ein Urlaubsband, zugeschnitten auf den Bereich, fuer den es Daten gibt.
    struct VacationBand: Identifiable {
        let id: String
        let start: Date
        let end: Date
        let label: String?
    }

    /// Urlaube auf den Datenbereich zuschneiden.
    ///
    /// Ohne das dehnt ein Eintrag, der in die Zukunft reicht (ein Uniblock bis
    /// Oktober etwa), die x-Achse bis dorthin - und rechts steht ein Fuenftel
    /// des Diagramms leer, weil es dafuer keine Messwerte gibt. Die
    /// Weboberflaeche macht dasselbe, nur ueber Indizes.
    private var clampedVacations: [VacationBand] {
        guard let first = points.first?.date.startOfDay(),
              let last = points.last?.date.startOfDay() else { return [] }
        return vacations.compactMap { vacation in
            let start = max(vacation.start.startOfDay(), first)
            let end = min(vacation.end.startOfDay(), last)
            guard start <= end else { return nil }
            return VacationBand(id: vacation.id, start: start, end: end, label: vacation.label)
        }
    }

    /// Der Wertebereich der y-Achse: alles, was gerade gezeichnet wird, plus
    /// etwas Luft. Der Korridor gehoert dazu - sonst laege er halb ausserhalb.
    private var yDomain: ClosedRange<Double> {
        var values: [Double] = []
        if visible.contains(.measured) { values += points.compactMap(\.measured) }
        if visible.contains(.avg7)     { values += points.compactMap(\.avg7) }
        if visible.contains(.avg14)    { values += points.compactMap(\.avg14) }
        if visible.contains(.avg30)    { values += points.compactMap(\.avg30) }
        if visible.contains(.target)   { values += points.compactMap(\.target) }
        if let corridor { values += [corridor.lower, corridor.upper] }

        guard let low = values.min(), let high = values.max() else { return 70...100 }
        let padding = max((high - low) * 0.08, 0.4)
        return (low - padding)...(high + padding)
    }

    private func samples(_ keyPath: KeyPath<WeightPoint, Double?>) -> [ChartSample] {
        WeightChartData.samples(points, keyPath)
    }

    private var averageSegments: [ChartSegment] {
        WeightChartData.averageSegments(points, visible: visible)
    }
}
