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
            ForEach(vacations) { vacation in
                RectangleMark(
                    xStart: .value("von", vacation.start.startOfDay()),
                    xEnd: .value("bis", vacation.end.startOfDay()))
                .foregroundStyle(Palette.vacation.opacity(0.16))
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
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
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

    private func samples(_ keyPath: KeyPath<WeightPoint, Double?>) -> [ChartSample] {
        WeightChartData.samples(points, keyPath)
    }

    private var averageSegments: [ChartSegment] {
        WeightChartData.averageSegments(points, visible: visible)
    }
}
