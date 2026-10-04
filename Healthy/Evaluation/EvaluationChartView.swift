import Charts
import SwiftUI

/// Je Frage eine Linie: das Mittel der letzten sieben Tage kraeftig, die
/// einzelnen Antworten blass als Punkte dahinter.
struct EvaluationChartView: View {

    struct Series: Identifiable {
        let id: UUID
        let color: Color
        let daily: [EvaluationChartData.Point]
        let mean: [EvaluationChartData.Point]
    }

    let series: [Series]
    let from: CalendarDate
    let to: CalendarDate

    private var spanDays: Int {
        Calendar(identifier: .gregorian)
            .dateComponents([.day], from: from.startOfDay(), to: to.startOfDay()).day ?? 0
    }

    var body: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.daily, id: \.date) { point in
                    PointMark(x: .value("Tag", point.date.startOfDay(), unit: .day),
                              y: .value("Wert", point.value))
                        .foregroundStyle(line.color.opacity(0.35))
                        .symbolSize(spanDays > 120 ? 6 : 16)
                }
                ForEach(Array(Self.runs(line.mean).enumerated()), id: \.offset) { run, points in
                    ForEach(points, id: \.date) { point in
                        LineMark(x: .value("Tag", point.date.startOfDay(), unit: .day),
                                 y: .value("Mittel", point.value),
                                 series: .value("Linie", "\(line.id)-\(run)"))
                            .foregroundStyle(line.color)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
            }
        }
        // Immer die ganze Skala: eine Achse, die sich an die Werte schmiegt,
        // machte aus einem Schritt von 7 auf 6 einen Absturz.
        .chartYScale(domain: 0.5...10.5)
        // Etwas Luft an den Seiten: heute liegt genau am rechten Rand, und ein
        // Punkt dort waere sonst zur Haelfte abgeschnitten.
        .chartXScale(domain: from.startOfDay()...to.startOfDay(),
                     range: .plotDimension(startPadding: 6, endPadding: 6))
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel { Text(date, format: xLabelFormat) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 4, 7, 10]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(String(format: "%.0f", number)).font(.caption2)
                    }
                }
            }
        }
        .frame(height: 240)
    }

    private var xLabelFormat: Date.FormatStyle {
        spanDays >= 150 ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.day().month(.abbreviated)
    }

    /// Zerlegt die Mittelwerte in Stuecke ohne Luecke - ueber eine Woche ohne
    /// Antwort soll keine Linie behaupten, dazwischen sei etwas gewesen.
    nonisolated static func runs(_ points: [EvaluationChartData.Point]) -> [[EvaluationChartData.Point]] {
        var runs: [[EvaluationChartData.Point]] = []
        for point in points {
            if let last = runs.last?.last, last.date.adding(days: 1) == point.date {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return runs
    }
}

/// Die Tage als Raster: je Spalte eine Woche, Montag oben. Je kraeftiger, desto
/// hoeher der Wert; leere Felder sind Tage ohne Antwort.
struct EvaluationHeatmap: View {

    let weeks: [[CalendarDate?]]
    let values: [CalendarDate: Int]
    let color: Color

    @State private var width: CGFloat = 0

    private let gap: CGFloat = 2
    private let maxCell: CGFloat = 18

    private var cell: CGFloat {
        guard !weeks.isEmpty, width > 0 else { return 0 }
        let fitting = (width - gap * CGFloat(weeks.count - 1)) / CGFloat(weeks.count)
        return max(1, min(maxCell, fitting))
    }

    var body: some View {
        Canvas { context, _ in
            for (column, week) in weeks.enumerated() {
                for (row, date) in week.enumerated() {
                    guard let date else { continue }
                    let rect = CGRect(x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap),
                                      width: cell, height: cell)
                    let shape = Path(roundedRect: rect, cornerRadius: min(3, cell / 4))
                    if let value = values[date] {
                        let strength = 0.15 + 0.85 * Double(value - 1) / 9
                        context.fill(shape, with: .color(color.opacity(strength)))
                    } else {
                        context.fill(shape, with: .color(Color.primary.opacity(0.06)))
                    }
                }
            }
        }
        .frame(height: cell * 7 + gap * 6)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityHidden(true)
    }
}
