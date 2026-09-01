import Charts
import SwiftUI

struct WeightChartView: View {

    let points: [WeightPoint]
    let vacations: [Vacation]
    let corridor: (lower: Double, upper: Double)?
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
            AxisMarks { value in
                AxisGridLine()
                if let weight = value.as(Double.self) {
                    AxisValueLabel {
                        Text(String(format: "%.0f", weight)).font(.caption2)
                    }
                }
            }
        }
        .frame(height: 260)
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
