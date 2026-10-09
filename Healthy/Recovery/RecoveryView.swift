import Charts
import SwiftUI

/// Die Recovery des Morgens: der grosse Ring, die vier Bausteine gegen die
/// eigene Baseline und die HRV ueber 30 oder 90 Tage mit ihrem Normalband.
///
/// Eine Seite im Dashboard, kein Tab - iOS zeigt hoechstens fuenf, und
/// gebraucht wird sie seltener als Essen und Gewicht. Gerechnet ist alles im
/// Weight Tracker (Vertrag §3); hier wird nur gezeigt.
struct RecoveryView: View {

    @State private var store = RecoveryStore()
    @State private var showingSleepNeed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = store.error {
                    ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                }
                if store.today == nil, store.isLoading {
                    LoadingPlaceholder()
                } else {
                    RecoveryRing(day: store.today, lineWidth: 16, mainFont: .largeTitle, subFont: .subheadline)
                        .frame(width: 210, height: 210)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("recoveryRing")
                }
                if let today = store.today, !today.components.isEmpty {
                    components(today)
                }
                hrv
            }
            .padding(16)
            // Platz fuer die schwebende Tab-Leiste, wie im Gewicht-Tab.
            .padding(.bottom, 60)
        }
        .navigationTitle("Recovery")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Schlafbedarf …") { showingSleepNeed = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingSleepNeed) { RecoverySettingsSheet(store: store) }
        .refreshable { await store.load() }
        .task { await store.load() }
        // Kam eine Nacht dazu, waehrend die Seite offen ist, gilt der neue Score.
        .onChange(of: HealthSync.shared.uploads) {
            Task { await store.load() }
        }
    }

    // MARK: - Bausteine

    private func components(_ day: RecoveryDay) -> some View {
        VStack(spacing: 16) {
            ForEach(day.components) { component in
                RecoveryComponentRow(component: component,
                                     method: component.key == .hrv ? day.hrvMethod : nil)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - HRV

    private var hrv: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("HRV").font(.headline)
                Spacer()
                if let trend = RecoveryFormat.trend(store.today?.hrvTrend) {
                    Text(trend)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(trendColor(store.today?.hrvTrend?.status))
                }
            }
            Picker("Zeitraum", selection: Binding(
                get: { store.range },
                set: { range in Task { await store.select(range) } })) {
                ForEach(RecoveryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HrvChart(days: store.history, from: store.historyFrom, to: .today())
        }
    }

    /// Unter dem Normalbereich ist der Trend das Warnzeichen, darueber gut.
    private func trendColor(_ status: TrendStatus?) -> Color {
        switch status {
        case .below: Tone.warn.color
        case .above: Tone.good.color
        default:     .secondary
        }
    }
}

/// Der Ring: Score in Prozent in der Farbe des Bands; beim Kalibrieren wie
/// viele Naechte schon da sind. Ein `GaugeView` wie die Tachos im Essen-Tab -
/// nur ohne Zielmarke: einen Zielwert gibt es hier nicht.
struct RecoveryRing: View {

    let day: RecoveryDay?
    var lineWidth: CGFloat = 9
    var mainFont: Font = .title2
    var subFont: Font = .caption2

    var body: some View {
        let ring = RecoveryFormat.ring(day)
        GaugeView(ratio: ring.ratio, tone: ring.tone, main: ring.main, sub: ring.sub,
                  lineWidth: lineWidth, mainFont: mainFont, subFont: subFont, showsTarget: false)
    }
}

/// Ein Baustein: Wert, Baseline und der Abstand zu ihr als Balken um die Mitte.
private struct RecoveryComponentRow: View {

    let component: RecoveryComponent
    let method: HrvMethod?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(RecoveryFormat.label(component.key))
                    .font(.subheadline.weight(.medium))
                if let method, method != .unknown {
                    Text(method.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(RecoveryFormat.value(component.key, component.value, unit: component.unit))
                    .font(.headline.monospacedDigit())
            }
            HStack(spacing: 12) {
                Text(RecoveryFormat.baseline(component) ?? "⌀ –")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .leading)
                ZBar(z: component.z)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Wie weit ein Baustein von der eigenen Baseline weg ist: ein Balken von der
/// Mitte nach rechts, wenn es besser war, nach links, wenn schlechter - bis
/// ±3. Der Dienst liefert z schon so, dass positiv besser heisst, auch beim
/// Puls; hier wird nichts umgedreht.
struct ZBar: View {

    let z: Double?

    static let limit = 3.0

    var body: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            let clamped = max(-Self.limit, min(Self.limit, z ?? 0))
            let length = half * abs(clamped) / Self.limit
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                if z != nil {
                    Capsule()
                        .fill(clamped >= 0 ? Tone.good.color : Tone.warn.color)
                        .frame(width: max(length, 3))
                        .offset(x: clamped >= 0 ? half : half - max(length, 3))
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1.5)
                    .offset(x: half - 0.75)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Die HRV je Nacht vor ihrem Normalband (Median ± 0,5 Streuung, je Tag vom
/// Dienst). Linie und Band reissen an Luecken ab.
struct HrvChart: View {

    let days: [RecoveryDay]
    let from: CalendarDate
    let to: CalendarDate

    var body: some View {
        let runs = RecoveryChartData.hrvRuns(days)
        let band = RecoveryChartData.bandRuns(days)
        Chart {
            ForEach(band) { run in
                ForEach(run.samples) { sample in
                    AreaMark(x: .value("Tag", sample.date),
                             yStart: .value("unten", sample.low),
                             yEnd: .value("oben", sample.high),
                             series: .value("Band", run.id))
                }
                .foregroundStyle(Palette.avg7.opacity(0.18))
                .interpolationMethod(.linear)
            }
            ForEach(runs) { run in
                if run.isSingle, let only = run.samples.first {
                    PointMark(x: .value("Tag", only.date), y: .value("ms", only.value))
                        .foregroundStyle(Palette.measured)
                        .symbolSize(20)
                } else {
                    ForEach(run.samples) { sample in
                        LineMark(x: .value("Tag", sample.date),
                                 y: .value("ms", sample.value),
                                 series: .value("Serie", run.id))
                    }
                    .foregroundStyle(Palette.measured)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                }
            }
        }
        .chartYScale(domain: RecoveryChartData.domain(days))
        // Etwas Luft an den Seiten: heute liegt am rechten Rand.
        .chartXScale(domain: from.startOfDay()...to.startOfDay(),
                     range: .plotDimension(startPadding: 6, endPadding: 6))
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel { Text(date, format: .dateTime.day().month(.abbreviated)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
                if let ms = value.as(Double.self) {
                    AxisValueLabel { Text(GermanNumber.string(ms)).font(.caption2) }
                }
            }
        }
        .frame(height: 220)
        .accessibilityIdentifier("hrvChart")
    }
}
