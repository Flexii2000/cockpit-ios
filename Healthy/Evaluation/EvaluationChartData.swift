import Foundation

/// Was die Diagramme des Evaluation-Tabs zeichnen.
///
/// Ausnahme von der Regel „gerechnet wird in den Diensten“: hinter diesem Tab
/// steht kein Dienst - die Antworten bleiben auf dem iPhone (Felix, 04.10.).
/// Also rechnet die App das Wenige selbst, und zwar nur hier.
enum EvaluationChartData {

    struct Point: Hashable, Sendable {
        let date: CalendarDate
        let value: Double
    }

    /// Wie viele Tage das gleitende Mittel zurueckschaut, heute eingeschlossen.
    static let meanWindow = 7

    /// Der erste Tag eines Zeitraums, der heute endet.
    static func start(of range: EvaluationRange, today: CalendarDate) -> CalendarDate {
        today.adding(days: -(range.days - 1))
    }

    /// Die Antworten einer Frage zwischen `from` und `to`, nach Tag sortiert.
    static func daily(_ data: EvaluationData, question: UUID,
                      from: CalendarDate, to: CalendarDate) -> [Point] {
        let key = question.uuidString
        return data.days
            .filter { $0.date >= from && $0.date <= to }
            .compactMap { day in day.values[key].map { Point(date: day.date, value: Double($0)) } }
            .sorted { $0.date < $1.date }
    }

    /// Das Mittel der letzten sieben Tage je Tag - rueckwaerts statt zentriert
    /// wie beim Gewicht: „wie war die letzte Woche“ ist hier die Frage, und ein
    /// zentriertes Fenster reichte am heutigen Rand in Tage, die noch kommen.
    /// Gemittelt wird ueber die Tage mit Antwort; ohne eine im Fenster kein Wert,
    /// dort setzt die Linie aus.
    static func trailingMean(_ data: EvaluationData, question: UUID,
                             from: CalendarDate, to: CalendarDate) -> [Point] {
        let key = question.uuidString
        var byDate: [CalendarDate: Int] = [:]
        for day in data.days {
            if let value = day.values[key] { byDate[day.date] = value }
        }
        var points: [Point] = []
        var date = from
        while date <= to {
            let window = (0..<meanWindow).compactMap { byDate[date.adding(days: -$0)] }
            if !window.isEmpty {
                points.append(Point(date: date, value: Double(window.reduce(0, +)) / Double(window.count)))
            }
            date = date.adding(days: 1)
        }
        return points
    }

    /// Die Wochen der Heatmap: je Spalte eine Woche von Montag bis Sonntag,
    /// Tage ausserhalb des Zeitraums als `nil` - so steht jeder Wochentag in
    /// derselben Zeile, und eine Luecke sieht man als Luecke.
    static func weeks(from: CalendarDate, to: CalendarDate) -> [[CalendarDate?]] {
        guard from <= to else { return [] }
        let monday = from.adding(days: -weekdayIndex(of: from))
        var weeks: [[CalendarDate?]] = []
        var weekStart = monday
        while weekStart <= to {
            weeks.append((0..<7).map { offset in
                let date = weekStart.adding(days: offset)
                return date >= from && date <= to ? date : nil
            })
            weekStart = weekStart.adding(days: 7)
        }
        return weeks
    }

    /// 0 fuer Montag bis 6 fuer Sonntag.
    static func weekdayIndex(of date: CalendarDate) -> Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date.startOfDay())
        return (weekday + 5) % 7
    }
}
