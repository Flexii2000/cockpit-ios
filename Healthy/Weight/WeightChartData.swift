import Foundation

/// Ein Punkt, wie ihn das Diagramm braucht: Zeitpunkt statt Kalendertag.
struct ChartSample: Identifiable, Equatable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Ein Stueck einer Linie. Getrennt wird dort, wo die Vollstaendigkeit des
/// Mittelungsfensters umschlaegt - der Rest wird gepunktet gezeichnet.
struct ChartSegment: Identifiable, Equatable, Sendable {
    let id: String
    let series: WeightSeries
    let complete: Bool
    let samples: [ChartSample]
}

extension ChartSegment {
    /// Derselbe Abschnitt auf einer anderen Skala - fuer Kurven, die in den
    /// Wertebereich des Diagramms hineingerechnet werden.
    func mapped(_ transform: (Double) -> Double) -> ChartSegment {
        ChartSegment(id: id, series: series, complete: complete,
                     samples: samples.map { ChartSample(date: $0.date, value: transform($0.value)) })
    }
}

private extension WeightPoint {
    var avg7Distance: Double? { avg7.flatMap { average in target.map { average - $0 } } }
    var avg30Distance: Double? { avg30.flatMap { average in target.map { average - $0 } } }
}

/// Aufbereitung der Rohpunkte fuers Diagramm.
///
/// Bewusst ausserhalb der View: das Zerlegen ist die einzige Stelle mit
/// echter Logik, und in einer View waere sie nicht zu testen.
enum WeightChartData {

    static func samples(_ points: [WeightPoint],
                        _ keyPath: KeyPath<WeightPoint, Double?>) -> [ChartSample] {
        points.compactMap { point in
            point[keyPath: keyPath].map {
                ChartSample(date: point.date.startOfDay(), value: $0)
            }
        }
    }

    /// Zerlegt eine Mittelwert-Serie an den Stellen, an denen
    /// `complete` umschlaegt.
    ///
    /// Der Punkt am Umschlag gehoert zu **beiden** Abschnitten. Ohne diese
    /// Ueberlappung klaffte genau dort eine Luecke in der Linie - sichtbar als
    /// abgerissene Kurve an dem Tag, an dem das Fenster nicht mehr voll ist.
    ///
    /// Das verbindende Stueck bekommt dabei die Flagge des **frueheren**
    /// Punktes. Genauso entscheidet es die Weboberflaeche
    /// (`incompleteDash`: `points[ctx.p1DataIndex]`), und andersherum waere
    /// der erste unvollstaendige Tag schon gepunktet, obwohl die Strecke
    /// dorthin noch aus vollen Fenstern stammt.
    static func segments(_ points: [WeightPoint],
                         series: WeightSeries,
                         value: KeyPath<WeightPoint, Double?>,
                         complete: KeyPath<WeightPoint, Bool>) -> [ChartSegment] {
        var result: [ChartSegment] = []
        var current: [ChartSample] = []
        var currentComplete: Bool?

        func flush() {
            // Ein einzelner Punkt ergibt keine Linie - der waere unsichtbar
            // und wuerde nur eine leere Serie erzeugen.
            guard let isComplete = currentComplete, current.count > 1 else { return }
            result.append(ChartSegment(id: "\(series.rawValue)-\(result.count)",
                                       series: series,
                                       complete: isComplete,
                                       samples: current))
        }

        for point in points {
            guard let raw = point[keyPath: value] else { continue }
            let sample = ChartSample(date: point.date.startOfDay(), value: raw)
            let isComplete = point[keyPath: complete]
            if currentComplete == nil {
                currentComplete = isComplete
            } else if isComplete != currentComplete {
                current.append(sample)
                flush()
                current = [sample]
                currentComplete = isComplete
                continue
            }
            current.append(sample)
        }
        flush()
        return result
    }

    // MARK: - Distanz z. Target

    /// „Distanz z. Target" (Vertrag §5): je Tag das Mittel des Zeitraums
    /// minus Zielkurve, nur wo beides da ist; positiv heisst ueber der Kurve.
    static func targetDistances(_ points: [WeightPoint], average: WeightSeries) -> [Double] {
        points.compactMap { $0[keyPath: distanceKeyPaths(average).value] }
    }

    /// Dieselbe Kurve in Abschnitten, gepunktet wie das Mittel dahinter -
    /// die Werte noch in kg, nicht auf der Skala des Diagramms.
    static func targetDistanceSegments(_ points: [WeightPoint], average: WeightSeries) -> [ChartSegment] {
        let paths = distanceKeyPaths(average)
        return segments(points, series: .targetDistance, value: paths.value, complete: paths.complete)
    }

    /// Der Wert eines Tages, fuer die Sprechblase.
    static func targetDistance(of point: WeightPoint, average: WeightSeries) -> Double? {
        point[keyPath: distanceKeyPaths(average).value]
    }

    /// Die Beschriftung der Skala: Vorzeichen, Komma, hoechstens eine
    /// Nachkommastelle, ohne Einheit - „+1", „+0,5", „0", „−0,5".
    static func distanceTick(_ value: Double) -> String {
        GermanNumber.string(value, decimals: value == value.rounded() ? 0 : 1, signed: true)
    }

    private static func distanceKeyPaths(_ average: WeightSeries)
        -> (value: KeyPath<WeightPoint, Double?>, complete: KeyPath<WeightPoint, Bool>) {
        if average == .avg30 {
            return (value: \WeightPoint.avg30Distance, complete: \WeightPoint.avg30Complete)
        }
        return (value: \WeightPoint.avg7Distance, complete: \WeightPoint.avg7Complete)
    }

    // MARK: - Rechte Seite

    /// Wem die Beschriftung rechts aussen gehoert (Vertrag §5): erst den kcal,
    /// dann dem Defizit, dann der Distanz. Wer leer ausgeht, steht klein
    /// innen - das Defizit rechts, die Distanz links.
    enum TrailingScale: Equatable {
        case none, kcal, deficit, targetDistance
    }

    /// - Parameter hasDailyDeficit: ob „Defizit Tag" Werte hat - es liegt auf
    ///   derselben Skala wie „Defizit ⌀" und braucht sie auch allein.
    static func trailingScale(visible: Set<WeightSeries>, hasDeficit: Bool,
                              hasDailyDeficit: Bool = false, hasDistance: Bool) -> TrailingScale {
        if !visible.isDisjoint(with: [.kcal, .kcalDay, .expenditure]) { return .kcal }
        if (visible.contains(.deficit) && hasDeficit)
            || (visible.contains(.deficitDay) && hasDailyDeficit) { return .deficit }
        if visible.contains(.targetDistance) && hasDistance { return .targetDistance }
        return .none
    }

    /// Alle sichtbaren Mittelwert-Serien in Abschnitten.
    static func averageSegments(_ points: [WeightPoint],
                                visible: Set<WeightSeries>) -> [ChartSegment] {
        let definitions: [(WeightSeries, KeyPath<WeightPoint, Double?>, KeyPath<WeightPoint, Bool>)] = [
            (.avg7, \.avg7, \.avg7Complete),
            (.avg14, \.avg14, \.avg14Complete),
            (.avg30, \.avg30, \.avg30Complete),
        ]
        return definitions
            .filter { visible.contains($0.0) }
            .flatMap { segments(points, series: $0.0, value: $0.1, complete: $0.2) }
    }
}
