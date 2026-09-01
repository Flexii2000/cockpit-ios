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
