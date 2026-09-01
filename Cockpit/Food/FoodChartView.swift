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
    /// Der gewaehlte Zeitraum. Bewusst von aussen gesetzt und nicht aus
    /// `history` abgeleitet: sonst zeigt das Diagramm nur die Tage, an denen
    /// etwas eingetragen wurde, und der Umschalter bliebe wirkungslos.
    let from: CalendarDate
    let to: CalendarDate
    /// Welche Gewichtskurven mitlaufen. Leer heisst: keine.
    let weightOverlay: Set<WeightSeries>

    var body: some View {
        Chart {
            if let kcalTarget {
                RuleMark(y: .value("Ziel", kcalTarget))
                    .foregroundStyle(Palette.kcal.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            // Kurve statt Saeulen - aber an jeder Luecke getrennt: Tage ohne
            // Eintrag liefert der Kalorienzaehler gar nicht, sie sind
            // unbekannt und nicht null.
            ForEach(kcalRuns) { run in
                if run.isSingle, let only = run.samples.first {
                    PointMark(x: .value("Tag", only.date),
                              y: .value("kcal", only.value))
                    .foregroundStyle(Palette.kcal)
                    .symbolSize(18)
                } else {
                    ForEach(run.samples) { sample in
                        LineMark(x: .value("Tag", sample.date),
                                 y: .value("kcal", sample.value),
                                 series: .value("Serie", run.id))
                    }
                    .foregroundStyle(Palette.kcal)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }

            // Was die Saeulenfarbe vorher trug: Tage deutlich ueber dem Ziel
            // bekommen einen Punkt, sonst ginge die Information verloren.
            ForEach(daysOverTarget) { sample in
                PointMark(x: .value("Tag", sample.date),
                          y: .value("kcal", sample.value))
                .foregroundStyle(Palette.over)
                .symbolSize(26)
            }

            // Gewicht: Mittel und Tageswerte einzeln zuschaltbar. Auch hier
            // an Luecken getrennt - an Tagen ohne Messung steht nichts.
            ForEach(weightRuns) { run in
                ForEach(run.samples) { sample in
                    LineMark(x: .value("Tag", sample.date, unit: .day),
                             y: .value("Gewicht", sample.value),
                             series: .value("Serie", run.id))
                }
                .foregroundStyle(run.id.hasPrefix(WeightSeries.measured.rawValue)
                                 ? Palette.measured : Palette.avg7)
                .lineStyle(StrokeStyle(
                    lineWidth: run.id.hasPrefix(WeightSeries.measured.rawValue) ? 1.3 : 2))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: kcalDomain)
        .chartXScale(domain: from.startOfDay()...to.startOfDay())
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                if let kcal = value.as(Double.self) {
                    AxisValueLabel { Text(kcal.whole).font(.caption2) }
                }
            }
            // Rechts die Kilogramm zur hineingerechneten Kurve - nur, wenn
            // sie ueberhaupt gezeigt wird.
            AxisMarks(position: .trailing,
                      values: weightOverlay.isEmpty ? [] : weightTicks.map(toKcalScale)) { value in
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
        .frame(height: 220)
    }

    // MARK: - Skalen (Rechnerei in FoodChartData, damit sie testbar ist)

    private var kcalDomain: ClosedRange<Double> {
        FoodChartData.kcalDomain(history, target: kcalTarget)
    }

    /// Alle sichtbaren Gewichtswerte - sie teilen sich eine Skala, sonst
    /// laegen Mittel und Tageswerte auf verschiedenen Hoehen.
    private var weightValues: [DayValue] {
        weightOverlay.flatMap {
            FoodChartData.weightValues(weightPoints, series: $0, from: from, to: to)
        }
    }

    private var weightRuns: [ChartRun] {
        weightOverlay.sorted { $0.rawValue < $1.rawValue }.flatMap { series in
            let mapped = FoodChartData
                .weightValues(weightPoints, series: series, from: from, to: to)
                .map { DayValue(date: $0.date, value: toKcalScale($0.value)) }
            return DaySeries.runs(mapped, key: series.rawValue)
        }
    }

    private var weightRange: ClosedRange<Double>? {
        FoodChartData.weightRange(weightValues)
    }

    private var kcalRuns: [ChartRun] {
        FoodChartData.kcalRuns(history)
    }

    private var daysOverTarget: [ChartSample] {
        FoodChartData.daysOverTarget(history, target: kcalTarget,
                                     tolerance: NutritionTone.kcalTolerance)
            .map { ChartSample(date: $0.date.startOfDay(), value: $0.value) }
    }

    private var weightTicks: [Double] {
        guard let range = weightRange else { return [] }
        let low = range.lowerBound, high = range.upperBound
        return [low + (high - low) * 0.2,
                low + (high - low) * 0.5,
                low + (high - low) * 0.8]
    }

    private func toKcalScale(_ weight: Double) -> Double {
        guard let range = weightRange else { return kcalDomain.lowerBound }
        return FoodChartData.scale(weight, from: range, to: kcalDomain)
    }

    private func fromKcalScale(_ value: Double) -> Double? {
        guard let range = weightRange else { return nil }
        return FoodChartData.scale(value, from: kcalDomain, to: range)
    }

    private func barColor(_ kcal: Double) -> Color {
        kcal > (kcalTarget ?? .infinity) ? Palette.over : Palette.kcal
    }
}
