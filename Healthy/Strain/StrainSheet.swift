import Charts
import SwiftUI

/// Das Strain-Fenster (Vertrag §5, Felix 10.11.): der Verlauf ueber Wochen und
/// Monate - oben der Strain je Tag gegen sein Ziel, darunter die Form-Kurve
/// (akute gegen gewohnte Last, mit der Recovery als Punkten).
///
/// Ein Blatt ueber dem Dashboard, keine Seite im Stapel: ein Blick in den
/// Verlauf, von dem man gleich zurueck will. Gerechnet ist alles im Weight
/// Tracker (§7); hier wird nur gezeigt.
struct StrainSheet: View {

    @State private var store = StrainStore()
    /// Der angetippte Tag - beide Diagramme zeigen denselben.
    @State private var selectedDay: CalendarDate?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = store.error {
                        ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                    }
                    Picker("Zeitraum", selection: Binding(
                        get: { store.range },
                        set: { range in
                            selectedDay = nil
                            Task { await store.select(range) }
                        })) {
                        ForEach(StrainRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !store.hasLoaded {
                        LoadingPlaceholder()
                    } else {
                        history
                        form
                    }
                }
                .padding(16)
            }
            .navigationTitle("Strain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .refreshable { await store.load() }
            .task { await store.load() }
            // Kam Puls dazu, waehrend das Fenster offen ist, gilt der neue Stand.
            .onChange(of: HealthSync.shared.uploads) {
                Task { await store.load() }
            }
        }
    }

    /// Wie in den anderen Diagrammen im Debug-Build vorwaehlbar - eine
    /// Ziehgeste laesst sich im Simulator nicht ausloesen.
    private var effectiveSelection: CalendarDate? {
        #if DEBUG
        if selectedDay == nil,
           let raw = ProcessInfo.processInfo.environment["COCKPIT_SELECT"] {
            return CalendarDate(iso: raw)
        }
        #endif
        return selectedDay
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Strain").font(.headline)
            StrainHistoryChart(days: store.days, from: store.from, to: .today(), range: store.range,
                               selection: effectiveSelection, select: { selectedDay = $0 })
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Form").font(.headline)
                Spacer()
                StrainLegendEntry(title: "Akut", color: Palette.strain)
                StrainLegendEntry(title: "Gewohnt", color: Palette.strainChronic)
            }
            StrainFormChart(days: store.days, from: store.from, to: .today(), range: store.range,
                            selection: effectiveSelection, select: { selectedDay = $0 })
        }
    }
}

/// Ein Eintrag der Legende ueber der Form-Kurve: ein Stueck Linie und ihr Name.
private struct StrainLegendEntry: View {

    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: 3)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Die Beschriftung der Zeitachse: in kurzen Zeitraeumen Tag und Monat, ab
/// einem halben Jahr Monat und Jahr - dort stuende sonst viermal ein „1.“.
private func strainAxisLabel(_ date: Date, range: StrainRange) -> Text {
    range.rawValue > 120
        ? Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits))
        : Text(date, format: .dateTime.day().month(.abbreviated))
}

/// Tippen und waagerechtes Ziehen waehlen einen Tag - senkrechte Bewegungen
/// gehoeren der Liste (wie im Verlauf des Essen-Tabs).
private struct StrainChartSelection: ViewModifier {

    let days: [CalendarDate]
    /// Um wie viel der beruehrte Zeitpunkt verschoben wird, bevor der naechste
    /// Tag gesucht wird: Balken stehen in der Mitte ihres Tages, Linienpunkte
    /// an seinem Beginn.
    let offset: TimeInterval
    let select: (CalendarDate?) -> Void

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            pick(value.location.x, proxy: proxy, geometry: geometry)
                        }
                        .onEnded { _ in select(nil) })
                    .simultaneousGesture(SpatialTapGesture()
                        .onEnded { tap in pick(tap.location.x, proxy: proxy, geometry: geometry) })
            }
        }
    }

    private func pick(_ location: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plot = proxy.plotFrame else { return }
        let x = location - geometry[plot].origin.x
        guard let date: Date = proxy.value(atX: x) else { return }
        select(ChartSelection.nearestDay(to: date.addingTimeInterval(offset), in: days))
    }
}

/// „Strain“: je Tag ein Balken auf der Skala 0–21, das Ziel als gestrichelte
/// Stufenlinie. Das Ziel laeuft auch ueber Tage ohne Histogramm weiter - dort
/// fehlt nur der Balken.
struct StrainHistoryChart: View {

    let days: [StrainDay]
    let from: CalendarDate
    let to: CalendarDate
    let range: StrainRange
    let selection: CalendarDate?
    let select: (CalendarDate?) -> Void

    var body: some View {
        let bars = StrainChartData.bars(days)
        let targets = StrainChartData.targetRuns(days)
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Tag", bar.date, unit: .day),
                        y: .value("Strain", bar.strain),
                        width: .ratio(barRatio))
                    .foregroundStyle(Palette.strain.opacity(bar.isPartial ? 0.55 : 1))
            }
            ForEach(targets) { run in
                if run.isSingle, let only = run.samples.first {
                    // Eine Stufe allein hat als Linie keine Laenge.
                    RuleMark(xStart: .value("Tag", only.date),
                             xEnd: .value("Tag", only.date.addingTimeInterval(86_400)),
                             y: .value("Ziel", only.value))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                } else {
                    ForEach(run.samples) { sample in
                        LineMark(x: .value("Tag", sample.date, unit: .day),
                                 y: .value("Ziel", sample.value),
                                 series: .value("Serie", run.id))
                    }
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.stepCenter)
                }
            }
            if let day = selection, let entries = entries(for: day), !entries.isEmpty {
                RuleMark(x: .value("Tag", day.startOfDay(), unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartCallout(title: day.short, entries: entries)
                    }
            }
        }
        .chartYScale(domain: 0...StrainFormat.scale)
        .chartXScale(domain: from.startOfDay()...to.adding(days: 1).startOfDay())
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel { strainAxisLabel(date, range: range) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 7, 14, 21]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
                if let strain = value.as(Double.self) {
                    AxisValueLabel { Text(GermanNumber.string(strain)).font(.caption2) }
                }
            }
        }
        // Balken stehen in der Mitte ihres Tages: ein Tipp darauf liegt einen
        // halben Tag hinter seinem Beginn.
        .modifier(StrainChartSelection(days: StrainChartData.selectableDays(days), offset: -43_200,
                                       select: select))
        .frame(height: 200)
        .accessibilityIdentifier("strainChart")
    }

    /// Ueber ein halbes Jahr ist ein Tag nur ein, zwei Punkte breit: dann ohne
    /// Luecke zwischen den Balken, sonst flimmert die Reihe.
    private var barRatio: CGFloat {
        range.rawValue > 120 ? 1 : 0.7
    }

    private func entries(for day: CalendarDate) -> [CalloutEntry]? {
        guard let found = days.first(where: { $0.date == day }) else { return nil }
        return StrainChartData.strainCallout(found).map { line in
            CalloutEntry(label: line.label, value: line.value,
                         color: line.label == "Strain" ? Palette.strain : Color.primary.opacity(0.7))
        }
    }
}

/// „Form“: die akute Last (7 Tage) gegen die gewohnte (28 Tage). Die Flaeche
/// dazwischen in „über Ziel“, wo Akut darueber liegt, sonst in der
/// Strain-Farbe; auf der Akut-Linie je Tag mit Recovery ein Punkt in der Farbe
/// ihres Bands.
struct StrainFormChart: View {

    let days: [StrainDay]
    let from: CalendarDate
    let to: CalendarDate
    let range: StrainRange
    let selection: CalendarDate?
    let select: (CalendarDate?) -> Void

    var body: some View {
        let segments = StrainChartData.formSegments(days)
        let acute = StrainChartData.acuteRuns(days)
        let chronic = StrainChartData.chronicRuns(days)
        let dots = StrainChartData.recoveryDots(days)
        Chart {
            // Die Flaeche zuerst - sie liegt hinter den Linien.
            ForEach(segments) { segment in
                ForEach(segment.points, id: \.date) { point in
                    AreaMark(x: .value("Tag", point.date),
                             yStart: .value("Gewohnt", point.intake),
                             yEnd: .value("Akut", point.expenditure),
                             series: .value("Fläche", segment.id))
                }
                .foregroundStyle(segment.isDeficit ? Palette.strainOverFill : Palette.strainFill)
                .interpolationMethod(.linear)
            }
            line(chronic, name: "Gewohnt", color: Palette.strainChronic)
            line(acute, name: "Akut", color: Palette.strain)
            ForEach(dots) { dot in
                PointMark(x: .value("Tag", dot.date), y: .value("Akut", dot.value))
                    .foregroundStyle(RecoveryFormat.tone(dot.band).gradient.last ?? .secondary)
                    .symbolSize(dotSize)
            }
            if let day = selection, let entries = entries(for: day), !entries.isEmpty {
                RuleMark(x: .value("Tag", day.startOfDay()))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartCallout(title: day.short, entries: entries)
                    }
            }
        }
        .chartYScale(domain: StrainChartData.loadDomain(days))
        // Etwas Luft an den Seiten: heute liegt am rechten Rand.
        .chartXScale(domain: from.startOfDay()...to.startOfDay(),
                     range: .plotDimension(startPadding: 6, endPadding: 6))
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel { strainAxisLabel(date, range: range) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
                if let load = value.as(Double.self) {
                    AxisValueLabel { Text(GermanNumber.string(load)).font(.caption2) }
                }
            }
        }
        .modifier(StrainChartSelection(days: StrainChartData.selectableDays(days), offset: 0, select: select))
        .frame(height: 200)
        .accessibilityIdentifier("formChart")
    }

    /// Ueber ein Jahr stehen die Punkte dicht - dort kleiner, damit die Linie
    /// darunter zu sehen bleibt.
    private var dotSize: CGFloat {
        switch range {
        case .sixWeeks: 28
        case .threeMonths: 20
        case .sixMonths: 12
        case .year: 7
        }
    }

    @ChartContentBuilder
    private func line(_ runs: [ChartRun], name: String, color: Color) -> some ChartContent {
        ForEach(runs) { run in
            if run.isSingle, let only = run.samples.first {
                PointMark(x: .value("Tag", only.date), y: .value(name, only.value))
                    .foregroundStyle(color)
                    .symbolSize(16)
            } else {
                ForEach(run.samples) { sample in
                    LineMark(x: .value("Tag", sample.date),
                             y: .value(name, sample.value),
                             series: .value("Serie", run.id))
                }
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)
            }
        }
    }

    private func entries(for day: CalendarDate) -> [CalloutEntry]? {
        guard let found = days.first(where: { $0.date == day }) else { return nil }
        return StrainChartData.formCallout(found).map { line in
            CalloutEntry(label: line.label, value: line.value,
                         color: line.label == "Akut" ? Palette.strain : Palette.strainChronic)
        }
    }
}
