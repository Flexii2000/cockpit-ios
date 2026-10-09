import Charts
import SwiftUI

/// Verlauf: die kcal (Mittel und Tageswert), das Tagesziel als Linie, der
/// Verbrauch, das Defizit und darueber die Gewichtskurve.
///
/// Swift Charts kennt nur **eine** y-Skala. Gewicht und Defizit werden
/// deshalb in den kcal-Bereich hineingerechnet und rechts mit eigenen
/// Beschriftungen versehen - die Kurve stimmt dadurch in ihrem Verlauf, und
/// die Achse sagt, welche Kilogramm bzw. kcal Defizit dahinterstehen.
struct FoodChartView: View {

    let history: [DayTotal]
    /// Das 7-Tage-Mittel dazu, fertig gerechnet vom Dienst.
    let averages: [DayAverage]
    let weightPoints: [WeightPoint]
    let kcalTarget: Double?
    /// Welche kcal-Kurven zu sehen sind: das Mittel (Vorgabe) und der Tageswert.
    let showAverage: Bool
    let showDaily: Bool
    /// „Verbrauch ⌀" aus dem Weight Tracker - hier vorgewaehlt: die Luecke
    /// zwischen ihm und „kcal ⌀" ist das Defizit.
    let expenditure: [DayAverage]
    let showExpenditure: Bool
    /// „Defizit ⌀" aus dem Weight Tracker, auf eigener Skala - hier
    /// vorgewaehlt. Mit „Verbrauch ⌀" und „kcal ⌀" faerbt es die Flaeche
    /// zwischen den beiden (Vertrag §5).
    let deficit: [DayAverage]
    let showDeficit: Bool
    /// Der gewaehlte Zeitraum. Bewusst von aussen gesetzt und nicht aus
    /// `history` abgeleitet: sonst zeigt das Diagramm nur die Tage, an denen
    /// etwas eingetragen wurde, und der Umschalter bliebe wirkungslos.
    let from: CalendarDate
    let to: CalendarDate
    /// Welche Gewichtskurven mitlaufen. Leer heisst: keine.
    let weightOverlay: Set<WeightSeries>

    @State private var selectedDay: CalendarDate?

    /// Wie im Gewicht-Tab im Debug-Build vorwaehlbar - eine Ziehgeste laesst
    /// sich im Simulator nicht ausloesen.
    private var effectiveSelection: CalendarDate? {
        #if DEBUG
        if selectedDay == nil,
           let raw = ProcessInfo.processInfo.environment["COCKPIT_SELECT"] {
            return CalendarDate(iso: raw)
        }
        #endif
        return selectedDay
    }

    var body: some View {
        Chart {
            // Die Flaeche zwischen Verbrauch und Aufnahme zuerst - sie liegt
            // hinter allen Linien.
            if showsBand {
                ForEach(bandSegments) { segment in
                    ForEach(segment.points, id: \.date) { point in
                        AreaMark(x: .value("Tag", point.date),
                                 yStart: .value("kcal ⌀", point.intake),
                                 yEnd: .value("Verbrauch ⌀", point.expenditure),
                                 series: .value("Fläche", segment.id))
                    }
                    .foregroundStyle(segment.isDeficit ? Palette.deficitFill : Palette.surplusFill)
                    .interpolationMethod(.linear)
                }
            }

            if let kcalTarget {
                RuleMark(y: .value("Ziel", kcalTarget))
                    .foregroundStyle(Palette.kcal.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            // Der Tageswert: blass und duenn, an jeder Luecke getrennt - Tage
            // ohne Eintrag liefert der Kalorienzaehler gar nicht, sie sind
            // unbekannt und nicht null.
            if showDaily {
                ForEach(kcalRuns) { run in
                    if run.isSingle, let only = run.samples.first {
                        PointMark(x: .value("Tag", only.date),
                                  y: .value("kcal", only.value))
                        .foregroundStyle(Palette.kcal.opacity(0.55))
                        .symbolSize(18)
                    } else {
                        ForEach(run.samples) { sample in
                            LineMark(x: .value("Tag", sample.date),
                                     y: .value("kcal", sample.value),
                                     series: .value("Serie", run.id))
                        }
                        .foregroundStyle(Palette.kcal.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.3))
                        // Bewusst keine Glaettung: eine Kurve durch die Punkte
                        // (Catmull-Rom) ueberschwingt zwischen weit
                        // auseinanderliegenden Werten und zeichnet damit Zahlen,
                        // die nie gemessen wurden.
                        .interpolationMethod(.linear)
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
            }

            // Das 7-Tage-Mittel - die eigentliche Kurve. Gepunktet, wo das
            // Fenster noch in die Zukunft reicht: die letzten drei Tage koennen
            // sich mit den naechsten Eintraegen noch aendern.
            if showAverage {
                ForEach(averageRuns) { run in
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
                        .lineStyle(StrokeStyle(lineWidth: 2.2, dash: run.complete ? [] : [1, 5]))
                        .interpolationMethod(.linear)
                    }
                }
            }

            // Der Verbrauch: dieselbe Form wie das kcal-Mittel, eigene Farbe.
            // Gestrichelt, solange sein Fenster nicht ganz vorbei ist.
            if showExpenditure {
                ForEach(expenditureRuns) { run in
                    if run.isSingle, let only = run.samples.first {
                        PointMark(x: .value("Tag", only.date),
                                  y: .value("kcal", only.value))
                        .foregroundStyle(Palette.expenditure)
                        .symbolSize(18)
                    } else {
                        ForEach(run.samples) { sample in
                            LineMark(x: .value("Tag", sample.date),
                                     y: .value("kcal", sample.value),
                                     series: .value("Serie", run.id))
                        }
                        .foregroundStyle(Palette.expenditure)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, dash: run.complete ? [] : [4, 4]))
                        .interpolationMethod(.linear)
                    }
                }
            }

            // Das Defizit auf eigener Skala: ueber der gestrichelten Nulllinie
            // Defizit, darunter Ueberschuss. Gestrichelt wie „Verbrauch ⌀",
            // solange das Fenster nicht ganz vorbei ist.
            if showDeficit && !deficit.isEmpty {
                RuleMark(y: .value("Defizit", deficitPosition(0)))
                    .foregroundStyle(Palette.deficit.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(deficitRuns) { run in
                    if run.isSingle, let only = run.samples.first {
                        PointMark(x: .value("Tag", only.date),
                                  y: .value("kcal", only.value))
                        .foregroundStyle(Palette.deficit)
                        .symbolSize(18)
                    } else {
                        ForEach(run.samples) { sample in
                            LineMark(x: .value("Tag", sample.date),
                                     y: .value("kcal", sample.value),
                                     series: .value("Serie", run.id))
                        }
                        .foregroundStyle(Palette.deficit)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, dash: run.complete ? [] : [4, 4]))
                        .interpolationMethod(.linear)
                    }
                }
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
                .interpolationMethod(.linear)
            }

            // Die Sprechblase zum angetippten Tag: alle sichtbaren Reihen,
            // wie im Gewicht-Diagramm. Zuletzt gezeichnet, damit keine Kurve
            // sie verdeckt.
            if let day = effectiveSelection, !entries(for: day).isEmpty {
                RuleMark(x: .value("Tag", day.startOfDay()))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    // `y: .fit(to: .chart)` haelt sie im Diagramm - sonst ragte
                    // sie nach oben ueber den Zeitraum-Umschalter.
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart),
                                                          y: .fit(to: .chart))) {
                        ChartCallout(title: day.short, entries: entries(for: day))
                    }
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
            // Ohne Kilogramm gehoert die rechte Seite dem Defizit - aussen wie
            // die kg-Skala. Mit ihnen steht es klein innen (`chartBackground`).
            AxisMarks(position: .trailing,
                      values: deficitOutside ? deficitScale.ticks.map(deficitPosition) : []) { value in
                if let mapped = value.as(Double.self) {
                    AxisValueLabel {
                        Text(GermanNumber.string(deficitScale.value(at: mapped, in: kcalDomain)))
                            .font(.caption2)
                            .foregroundStyle(Palette.deficit)
                    }
                }
            }
        }
        // Der Titel der Defizit-Skala, wenn sie aussen steht (Vertrag §5).
        .chartYAxisLabel(position: .top, alignment: .trailing, spacing: 4) {
            if deficitOutside {
                Text("Defizit")
                    .font(.caption2)
                    .foregroundStyle(Palette.deficit)
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
        // Hinter den Kurven: die Sprechblase soll die kleinen Zahlen
        // verdecken, nicht umgekehrt.
        .chartBackground { proxy in
            GeometryReader { geometry in
                if deficitInside, let plot = proxy.plotFrame {
                    DeficitInsideLabels(scale: deficitScale, target: kcalDomain,
                                        proxy: proxy, plot: geometry[plot])
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    // `simultaneousGesture` und eine Mindeststrecke, nicht
                    // `gesture(minimumDistance: 0)`: sonst nimmt das Diagramm
                    // jede Beruehrung fuer sich und die Seite laesst sich nicht
                    // mehr scrollen, sobald der Finger darauf landet. Der
                    // UI-Test hat genau das gefunden - zweimal nach oben
                    // gewischt, und die Karte darunter blieb angeschnitten.
                    .simultaneousGesture(DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            // Nur waagerechte Bewegungen lesen Werte ab.
                            // Senkrechte gehoeren der Liste.
                            guard abs(value.translation.width)
                                    > abs(value.translation.height) else { return }
                            guard let plot = proxy.plotFrame else { return }
                            let x = value.location.x - geometry[plot].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            // Der Verlauf hat nur an Tagen mit Eintrag Werte -
                            // gesucht wird trotzdem im ganzen Fenster, sonst
                            // springt die Markierung ueber Luecken.
                            selectedDay = ChartSelection.nearestDay(
                                to: date, in: tageImDiagramm)
                        }
                        .onEnded { _ in selectedDay = nil })
                    .simultaneousGesture(SpatialTapGesture()
                        .onEnded { tap in
                            // Antippen soll auch ohne Bewegung einen Wert
                            // zeigen - eine Ziehgeste mit Mindeststrecke tut
                            // das nicht mehr.
                            guard let plot = proxy.plotFrame else { return }
                            let x = tap.location.x - geometry[plot].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            selectedDay = ChartSelection.nearestDay(
                                to: date, in: tageImDiagramm)
                        })
            }
        }
        .frame(height: 220)
    }

    /// Die Tage, auf die sich eine Beruehrung zuordnen laesst. Der Verlauf hat
    /// nur an Tagen mit Eintrag Werte - dazwischen springt die Markierung auf
    /// den naechstgelegenen.
    private var tageImDiagramm: [CalendarDate] {
        Array(Set(history.map(\.date) + averages.map(\.date) + expenditure.map(\.date)
                  + deficit.map(\.date))).sorted()
    }

    /// Alle sichtbaren Reihen fuer diesen Tag.
    private func entries(for day: CalendarDate) -> [CalloutEntry] {
        var result: [CalloutEntry] = []
        if showAverage, let average = averages.first(where: { $0.date == day }) {
            result.append(CalloutEntry(label: "kcal ⌀", value: average.kcal.whole,
                                       color: Palette.kcal))
        }
        if showDaily, let total = history.first(where: { $0.date == day }) {
            result.append(CalloutEntry(label: "kcal", value: total.consumed.kcal.whole,
                                       color: Palette.kcal.opacity(0.55)))
        }
        if showExpenditure, let spent = expenditure.first(where: { $0.date == day }) {
            result.append(CalloutEntry(label: "Verbrauch ⌀", value: GermanNumber.string(spent.kcal),
                                       color: Palette.expenditure))
        }
        // Der Wert aus der unveraenderten Reihe, nicht aus der hineingerechneten.
        if showDeficit, let average = deficit.first(where: { $0.date == day }) {
            result.append(CalloutEntry(label: "Defizit ⌀ 7 Tage", value: EnergyFormat.kcal(average.kcal),
                                       color: Palette.deficit))
        }
        for series in [WeightSeries.avg7, .measured] where weightOverlay.contains(series) {
            if let value = FoodChartData
                .weightValues(weightPoints, series: series, from: day, to: day).first {
                result.append(CalloutEntry(
                    label: series == .avg7 ? "Gewicht ⌀" : "Gewicht",
                    value: value.value.kg,
                    color: series == .avg7 ? Palette.avg7 : Palette.measured))
            }
        }
        return result
    }

    // MARK: - Skalen (Rechnerei in FoodChartData, damit sie testbar ist)

    private var kcalDomain: ClosedRange<Double> {
        FoodChartData.kcalDomain(daily: showDaily ? history : [],
                                 averages: showAverage ? averages : [],
                                 expenditure: showExpenditure ? expenditure : [],
                                 target: kcalTarget)
    }

    private var averageRuns: [AverageRun] {
        FoodChartData.averageRuns(averages)
    }

    private var expenditureRuns: [AverageRun] {
        FoodChartData.expenditureRuns(expenditure)
    }

    private var deficitScale: DeficitScale {
        DeficitScale(values: deficit.map(\.kcal))
    }

    private func deficitPosition(_ value: Double) -> Double {
        deficitScale.position(value, in: kcalDomain)
    }

    private var deficitRuns: [AverageRun] {
        FoodChartData.deficitRuns(deficit, scale: deficitScale, onto: kcalDomain)
    }

    /// Rechts aussen steht die Defizit-Skala nur, solange dort keine
    /// Kilogramm stehen.
    private var deficitOutside: Bool {
        showDeficit && !deficit.isEmpty && weightOverlay.isEmpty
    }

    private var deficitInside: Bool {
        showDeficit && !deficit.isEmpty && !weightOverlay.isEmpty
    }

    /// Die Flaeche gehoert zu „Defizit ⌀" und braucht beide Kurven, die sie
    /// einfassen (Vertrag §5).
    private var showsBand: Bool {
        showDeficit && showExpenditure && showAverage
    }

    private var bandSegments: [BandSegment] {
        EnergyBand.segments(expenditure: expenditure, intake: averages)
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
