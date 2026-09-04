import Charts
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

struct WeightChartView: View {

    let points: [WeightPoint]
    let vacations: [Vacation]
    let corridor: (lower: Double, upper: Double)?
    let kcalByDay: [DayValue]
    let kcalTarget: Double?
    let visible: Set<WeightSeries>

    @State private var selectedDay: CalendarDate?

    /// Im Debug-Build vorwaehlbar: eine Ziehgeste laesst sich im Simulator
    /// nicht ausloesen, und ohne Vorauswahl waere die Sprechblase nie im Bild
    /// zu sehen.
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
            // Urlaube ganz nach hinten: sie sind Hintergrund, keine Serie.
            ForEach(clampedVacations) { band in
                RectangleMark(
                    xStart: .value("von", band.start),
                    xEnd: .value("bis", band.end))
                // Leise: ein Hauch Farbe, keine Kante. Das Band ist Kontext,
                // die Kurve ist die Hauptsache.
                .foregroundStyle(Palette.vacation.opacity(0.09))
                .annotation(position: .overlay, alignment: .topLeading, spacing: 0) {
                    // Die Beschriftung sitzt IM Band, oben links, als kleine
                    // Pille - nicht frei ueber dem Diagramm, wo sie mit der
                    // Achse und der Sprechblase um Platz kaempft. In langen
                    // Ansichten sind die Baender nur ein paar Pixel breit;
                    // dann keine Beschriftung, sonst Buchstabensalat.
                    if let label = band.label, !label.isEmpty, isWide(band) {
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Palette.vacation)
                            // Nicht umbrechen, auch wenn das Band schmaler ist
                            // als das Wort - lieber ragt die Pille heraus, als
                            // dass "Urlaub" zu drei Zeilen wird.
                            .fixedSize()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.vacation.opacity(0.14)))
                            .padding(4)
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
                        // Bewusst keine Glaettung: eine Kurve durch die Punkte (Catmull-Rom)
                // ueberschwingt zwischen weit auseinanderliegenden Werten und
                // zeichnet damit Zahlen, die nie gemessen wurden. Gerade
                // Verbindungen behaupten nur, was zwischen zwei Messungen
                // plausibel ist: nichts.
                        .interpolationMethod(.linear)
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
                .interpolationMethod(.linear)
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
                .interpolationMethod(.linear)
            }

            if let day = effectiveSelection, let point = point(on: day) {
                RuleMark(x: .value("Tag", day.startOfDay()))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    // `y: .fit(to: .chart)` haelt sie im Diagramm. Ohne das
                    // ragt sie nach oben hinaus und verdeckt den
                    // Zeitraum-Umschalter darueber.
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart),
                                                          y: .fit(to: .chart))) {
                        ChartCallout(title: day.short, entries: entries(for: point))
                    }
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
            // Keine senkrechten Gitterlinien: sie zerschneiden die Kurve in
            // Kaestchen, ohne etwas zu sagen, das die Beschriftung nicht sagt.
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel { Text(date, format: xLabelFormat) }
                }
            }
        }
        .chartYAxis {
            // Kilogramm links, kcal rechts. Zwei Skalen kennt Swift Charts
            // nicht - die kcal sind in den Gewichtsbereich hineingerechnet,
            // und diese Achse sagt, welche Werte dahinterstehen.
            AxisMarks(position: .leading) { value in
                // Waagerecht nur angedeutet - man soll die Hoehe ablesen
                // koennen, nicht ein Raster sehen.
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.07))
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    // Der Wert steht, sobald der Finger aufliegt. Wem die
                    // Beruehrung gehoert, entscheidet die erste deutliche
                    // Bewegung: eher seitwaerts heisst ablesen, und die
                    // Liste bleibt stehen; eher hoch oder runter heisst
                    // scrollen, und der Wert verschwindet wieder. Ein Tipp
                    // ohne Bewegung laesst den Wert stehen, bis man woanders
                    // tippt. Vorher musste man erst kurz halten - das kam
                    // als Verzoegerung an.
                    .gesture(ScrubGesture(
                        onChange: { location in select(at: location.x, in: proxy, geometry) },
                        onEnd: { wasTap in if !wasTap { selectedDay = nil } }))
            }
        }
        // Hoeher als vorher (260): die Kurve schwankt um wenige Kilogramm,
        // und in 260 Punkten war der Verlauf ein flacher Strich.
        .frame(height: 340)
    }

    private func select(at x: CGFloat, in proxy: ChartProxy, _ geometry: GeometryProxy) {
        guard let plot = proxy.plotFrame else { return }
        let inPlot = x - geometry[plot].origin.x
        guard let date: Date = proxy.value(atX: inPlot) else { return }
        let day = ChartSelection.nearestDay(to: date, in: tageImDiagramm)
        if day != selectedDay {
            selectedDay = day
            // Ein leises Ticken je Tag - so merkt der Finger, dass er liest.
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Die Tage, auf die sich eine Beruehrung zuordnen laesst.
    private var tageImDiagramm: [CalendarDate] { points.map(\.date) }

    private func point(on day: CalendarDate) -> WeightPoint? {
        points.first { $0.date == day }
    }

    /// Alle sichtbaren Serien fuer diesen Tag - dieselbe Auswahl wie im
    /// Browser, wo Chart.js im Modus `index` alle Reihen der Stelle zeigt.
    private func entries(for point: WeightPoint) -> [CalloutEntry] {
        var result: [CalloutEntry] = []
        if visible.contains(.measured), let value = point.measured {
            result.append(CalloutEntry(label: "Messwert", value: value.kg,
                                       color: Palette.measured))
        }
        if visible.contains(.avg7), let value = point.avg7 {
            result.append(CalloutEntry(label: "7-Tage", value: value.kg, color: Palette.avg7))
        }
        if visible.contains(.avg14), let value = point.avg14 {
            result.append(CalloutEntry(label: "14-Tage", value: value.kg, color: Palette.avg14))
        }
        if visible.contains(.avg30), let value = point.avg30 {
            result.append(CalloutEntry(label: "30-Tage", value: value.kg, color: Palette.avg30))
        }
        if visible.contains(.target), let value = point.target {
            result.append(CalloutEntry(label: "Ziel", value: value.kg, color: Palette.target))
        }
        // Der kcal-Wert kommt aus der unveraenderten Reihe, nicht aus der in
        // die Gewichtsskala hineingerechneten - sonst staende dort eine Zahl,
        // die nur fuer die Zeichnung existiert.
        if visible.contains(.kcal),
           let kcal = kcalByDay.first(where: { $0.date == point.date }) {
            result.append(CalloutEntry(label: "kcal", value: kcal.value.whole,
                                       color: Palette.kcal))
        }
        return result
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

    /// Wie viele Tage die Ansicht umspannt.
    private var spanDays: Int {
        guard let first = points.first?.date, let last = points.last?.date else { return 0 }
        return max(last.daysFromToday() - first.daysFromToday(), 0)
    }

    /// Das Achsenformat richtet sich nach der Spanne.
    ///
    /// Ueber Jahre hinweg ist „1. Jan" ohne Jahreszahl wertlos - und genau das
    /// stand dort, weil das Format fuer kurze Zeitraeume gewaehlt war.
    private var xLabelFormat: Date.FormatStyle {
        switch spanDays {
        case 800...:  .dateTime.year()
        case 150...:  .dateTime.month(.abbreviated).year(.twoDigits)
        default:      .dateTime.day().month(.abbreviated)
        }
    }

    /// Ist das Band breit genug, um beschriftet zu werden?
    private func isWide(_ band: VacationBand) -> Bool {
        guard spanDays > 0 else { return false }
        let days = Calendar(identifier: .gregorian)
            .dateComponents([.day], from: band.start, to: band.end).day ?? 0
        return Double(days) / Double(spanDays) > 0.08
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

/// Ablesen ab dem Auflegen des Fingers.
///
/// SwiftUIs Gesten kommen hier nicht hin: `LongPressGesture` kennt keine
/// Position und wartet, `DragGesture` streitet sich mit der Liste ums
/// Scrollen. Darunter sitzt deshalb ein eigener UIKit-Erkenner (siehe
/// `ScrubRecognizer`), der beim Auflegen sofort meldet und erst an der
/// ersten deutlichen Bewegung entscheidet, wem die Beruehrung gehoert.
private struct ScrubGesture: UIGestureRecognizerRepresentable {

    let onChange: (CGPoint) -> Void
    /// `wasTap`: der Finger hat sich nicht bewegt - der Wert bleibt stehen.
    let onEnd: (_ wasTap: Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> ScrubRecognizer {
        let recognizer = ScrubRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: ScrubRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation)
        case .ended:
            onEnd(!recognizer.isScrubbing)
        case .cancelled, .failed:
            onEnd(false)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Solange nicht entschieden ist, darf die Liste mit zuhoeren - sonst
        /// waere das Scrollen schon beim Auflegen verloren. Sobald abgelesen
        /// wird, bleibt sie stehen.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !((recognizer as? ScrubRecognizer)?.isScrubbing ?? false)
        }
    }
}

/// Meldet beim Auflegen sofort (`began`), folgt dem Finger (`changed`) und
/// entscheidet an der ersten Bewegung ueber `decisionDistance` hinaus: geht
/// sie eher seitwaerts, ist es Ablesen, und der Erkenner haelt fortan das
/// Scrollen ab; geht sie eher hoch oder runter, gibt er auf, und die Liste
/// scrollt wie gewohnt.
final class ScrubRecognizer: UIGestureRecognizer {

    /// Ab dieser Bewegung ist entschieden. Kleiner als die Hysterese der
    /// Liste, damit die Entscheidung hier faellt und nicht dort.
    private let decisionDistance: CGFloat = 8

    private var start: CGPoint = .zero
    /// Entschieden fuer Ablesen - ab jetzt bleibt die Liste stehen.
    private(set) var isScrubbing = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible, let touch = touches.first else { return }
        start = touch.location(in: view)
        isScrubbing = false
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, state == .began || state == .changed else { return }
        let point = touch.location(in: view)
        if !isScrubbing {
            let dx = abs(point.x - start.x), dy = abs(point.y - start.y)
            guard max(dx, dy) >= decisionDistance else { return }
            if dy > dx {
                state = .cancelled
                return
            }
            isScrubbing = true
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        super.reset()
        isScrubbing = false
    }

    /// Andere (die Liste) erst abhalten, wenn abgelesen wird.
    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { isScrubbing }
    /// Und sich von niemandem abhalten lassen - ob die Liste scrollt,
    /// entscheidet dieser Erkenner selbst.
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}
