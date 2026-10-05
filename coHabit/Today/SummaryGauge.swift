import Foundation

/// Was in „Heute" den Stand eines Co-Habits zeigt (Felix, 2026-10-05): ein
/// Balken wie beim Ziel, wo es ein Ziel zum Auffuellen gibt, bei manuellen
/// Streaks die Punkte der Woche, sonst nichts.
enum SummaryGauge: Equatable {
    /// Gefuellt bis `fraction` (0…1, mehr wird abgeschnitten).
    case bar(Double)
    /// „●●○": erledigt gegen Soll im laufenden Zeitraum (hoechstens sieben).
    case weekDots(done: Int, goal: Int)
    case none
}

extension CohabitSummary {
    /// Automatische Quellen mit einem Ziel zum Auffuellen: Schritte je Woche
    /// und Fokus-Zeit. Track food, das kcal-Ziel im Wochenmittel und die
    /// Evaluation haben keins, das sich als Balken lesen liesse - und eine
    /// Quelle, die die App nicht kennt, bekommt erst recht keinen.
    static let barSources: Set<String> = ["STEPS_WEEKLY", "FOCUS"]

    var gauge: SummaryGauge {
        guard let progress else { return .none }
        if let source = ref.autoSource {
            return Self.barSources.contains(source) ? .bar(progress.fraction) : .none
        }
        switch ref.type {
        // Challenge: der eigene Stand gegen den Zielwert bzw. den Fuehrenden
        // (der Dienst rechnet ihn, seit 2026-10-05).
        case .goal, .challenge:
            return .bar(progress.fraction)
        case .streak:
            guard progress.goal >= 1, progress.goal <= 7 else { return .none }
            return .weekDots(done: Int(progress.done), goal: Int(progress.goal))
        case .abstinence:
            return .none
        }
    }
}
