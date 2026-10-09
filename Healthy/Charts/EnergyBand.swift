import Foundation

/// Ein Punkt der Flaeche zwischen „Verbrauch ⌀" und „kcal ⌀".
struct BandPoint: Equatable, Sendable {
    let date: Date
    let expenditure: Double
    let intake: Double
}

/// Ein zusammenhaengendes Stueck der Flaeche in einer Farbe.
struct BandSegment: Identifiable, Equatable, Sendable {
    let id: String
    /// Der Verbrauch liegt darueber - Defizit-Farbe; sonst Ueberschuss-Farbe.
    let isDeficit: Bool
    let points: [BandPoint]
}

/// Die Flaeche zwischen „Verbrauch ⌀" und „kcal ⌀" (Vertrag §5): die Luecke
/// zwischen den gezeigten Kurven, gefaerbt nach dem, was oben liegt. Sie
/// gehoert zu „Defizit ⌀", rechnet aber mit den Kurven selbst - in Wochen mit
/// lueckenhaften Eintraegen ist sie breiter, als die Linie hoch ist.
enum EnergyBand {

    /// Zerlegt die Flaeche in Stuecke einer Farbe.
    ///
    /// Nur wo beide Kurven einen Wert haben, und an jeder Luecke einer der
    /// beiden getrennt - wie die Linien selbst. Kreuzen sie sich zwischen zwei
    /// Tagen, wechselt die Farbe am Schnittpunkt, nicht am Tagesrand: die
    /// Linien sind zwischen den Tagen gerade (`.linear`), der Schnittpunkt
    /// laesst sich also genau ausrechnen, und beide Stuecke enden dort.
    /// - Parameter map: rechnet die kcal auf die Skala des Diagramms um (das
    ///   Gewicht-Diagramm zeichnet sie in den Gewichtsbereich hinein). Die
    ///   Umrechnung ist linear, der Schnittpunkt bleibt derselbe.
    static func segments(expenditure: [DayAverage], intake: [DayAverage],
                         map: (Double) -> Double = { $0 },
                         in timeZone: TimeZone = .current) -> [BandSegment] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let intakeByDay = Dictionary(intake.map { ($0.date, $0.kcal) }, uniquingKeysWith: { _, last in last })
        let points = expenditure
            .sorted { $0.date < $1.date }
            .compactMap { day in
                intakeByDay[day.date].map {
                    BandPoint(date: day.date.startOfDay(in: timeZone), expenditure: day.kcal, intake: $0)
                }
            }

        var result: [BandSegment] = []
        var current: [BandPoint] = []
        // `nil`, solange die Kurven im Stueck nur aufeinanderliegen.
        var currentIsDeficit: Bool?

        func flush() {
            // Ein einzelner Punkt hat keine Breite - dort gibt es nichts zu fuellen.
            if current.count > 1 {
                result.append(BandSegment(
                    id: "band-\(result.count)", isDeficit: currentIsDeficit ?? true,
                    points: current.map {
                        BandPoint(date: $0.date, expenditure: map($0.expenditure), intake: map($0.intake))
                    }))
            }
            current = []
            currentIsDeficit = nil
        }

        for point in points {
            let difference = point.expenditure - point.intake
            if let previous = current.last {
                // Ueber den Kalender gezaehlt: an einem Sommerzeitwechsel hat
                // ein Tag keine 86.400 Sekunden.
                let gap = calendar.dateComponents([.day], from: previous.date, to: point.date).day ?? 0
                if gap != 1 {
                    flush()
                } else if difference != 0, let isDeficit = currentIsDeficit, (difference > 0) != isDeficit {
                    let crossing = Self.crossing(from: previous, to: point)
                    if crossing != previous { current.append(crossing) }
                    flush()
                    current = [crossing]
                }
            }
            current.append(point)
            if currentIsDeficit == nil, difference != 0 { currentIsDeficit = difference > 0 }
        }
        flush()
        return result
    }

    /// Wo sich die beiden Kurven zwischen zwei Tagen schneiden. Liegen sie am
    /// ersten schon aufeinander, ist es dieser.
    private static func crossing(from start: BandPoint, to end: BandPoint) -> BandPoint {
        let before = start.expenditure - start.intake
        let after = end.expenditure - end.intake
        guard before != after else { return start }
        let share = before / (before - after)
        let value = start.expenditure + share * (end.expenditure - start.expenditure)
        return BandPoint(date: start.date.addingTimeInterval(share * end.date.timeIntervalSince(start.date)),
                         expenditure: value, intake: value)
    }
}
