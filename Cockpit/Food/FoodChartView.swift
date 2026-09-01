import Charts
import SwiftUI

/// Verlauf: kcal je Tag als Saeulen, das Tagesziel als Linie, darueber die
/// Gewichtskurve.
///
/// Swift Charts kennt nur **eine** y-Skala. Das Gewicht wird deshalb in den
/// kcal-Bereich hineingerechnet und rechts mit eigenen Beschriftungen
/// versehen - die Kurve stimmt dadurch in ihrem Verlauf, und die Achse sagt,
/// welche Kilogramm dahinterstehen.
struct FoodChartView: View {

    let history: [DayTotal]
    let weightPoints: [WeightPoint]
    let kcalTarget: Double?

    var body: some View {
        Chart {
            ForEach(history) { total in
                BarMark(
                    x: .value("Tag", total.date.startOfDay(), unit: .day),
                    yStart: .value("von", kcalDomain.lowerBound),
                    yEnd: .value("kcal", max(total.consumed.kcal, kcalDomain.lowerBound)))
                .foregroundStyle(barColor(total.consumed.kcal))
                .cornerRadius(2)
            }

            if let kcalTarget {
                RuleMark(y: .value("Ziel", kcalTarget))
                    .foregroundStyle(Palette.kcal.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            ForEach(mappedWeight) { sample in
                LineMark(x: .value("Tag", sample.date, unit: .day),
                         y: .value("Gewicht", sample.value),
                         series: .value("Serie", "weight"))
                .foregroundStyle(Palette.avg7)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: kcalDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                if let kcal = value.as(Double.self) {
                    AxisValueLabel { Text(kcal.whole).font(.caption2) }
                }
            }
            // Rechts die Kilogramm zur hineingerechneten Kurve.
            AxisMarks(position: .trailing, values: weightTicks.map(toKcalScale)) { value in
                if let mapped = value.as(Double.self),
                   let kilograms = fromKcalScale(mapped) {
                    AxisValueLabel {
                        Text(kilograms.oneDecimal)
                            .font(.caption2)
                            .foregroundStyle(Palette.avg7)
                    }
                }
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
        .frame(height: 220)
    }

    private func barColor(_ kcal: Double) -> Color {
        guard let kcalTarget, kcal > kcalTarget + NutritionTone.kcalTolerance else {
            return Palette.kcal.opacity(0.85)
        }
        return Color(hex: 0xEF5350).opacity(0.9)
    }

    // MARK: - Skalen

    /// Nullpunkt der kcal-Achse. Nicht 0: ein Tag liegt praktisch nie unter
    /// ~1000 kcal, und eine bei null beginnende Achse presst den
    /// interessanten Bereich in ein paar Pixel zusammen.
    private static let axisBase: Double = 1500

    private var kcalDomain: ClosedRange<Double> {
        let values = history.map(\.consumed.kcal) + [kcalTarget].compactMap { $0 }
        let lower = min(Self.axisBase, (values.min() ?? Self.axisBase) - 100)
        let upper = max((values.max() ?? 2500) + 150, (kcalTarget ?? 2000) * 1.1)
        return lower...max(upper, lower + 100)
    }

    private var weightRange: ClosedRange<Double>? {
        let values = weightPoints.compactMap { $0.avg7 ?? $0.measured }
        guard let low = values.min(), let high = values.max() else { return nil }
        // Etwas Luft, sonst klebt die Kurve am Rand.
        let padding = max((high - low) * 0.3, 0.5)
        return (low - padding)...(high + padding)
    }

    private var mappedWeight: [ChartSample] {
        guard weightRange != nil else { return [] }
        let firstDay = history.first?.date.startOfDay()
        return weightPoints.compactMap { point in
            guard let raw = point.avg7 ?? point.measured else { return nil }
            let day = point.date.startOfDay()
            // Nur den Ausschnitt zeichnen, der auch kcal-Saeulen hat.
            if let firstDay, day < firstDay { return nil }
            return ChartSample(date: day, value: toKcalScale(raw))
        }
    }

    private var weightTicks: [Double] {
        guard let range = weightRange else { return [] }
        let low = range.lowerBound, high = range.upperBound
        return [low + (high - low) * 0.2,
                low + (high - low) * 0.5,
                low + (high - low) * 0.8]
    }

    private func toKcalScale(_ weight: Double) -> Double {
        guard let range = weightRange, range.upperBound > range.lowerBound else {
            return kcalDomain.lowerBound
        }
        let share = (weight - range.lowerBound) / (range.upperBound - range.lowerBound)
        return kcalDomain.lowerBound + share * (kcalDomain.upperBound - kcalDomain.lowerBound)
    }

    private func fromKcalScale(_ value: Double) -> Double? {
        guard let range = weightRange,
              kcalDomain.upperBound > kcalDomain.lowerBound else { return nil }
        let share = (value - kcalDomain.lowerBound)
            / (kcalDomain.upperBound - kcalDomain.lowerBound)
        return range.lowerBound + share * (range.upperBound - range.lowerBound)
    }
}
