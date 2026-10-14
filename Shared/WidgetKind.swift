import Foundation

/// Die Kennung der Kachel.
///
/// Steht hier, weil sie in `StaticConfiguration(kind:)` **und** in
/// `WidgetCenter.reloadTimelines(ofKind:)` identisch sein muss. Zwei
/// Zeichenketten, die auseinanderlaufen koennen, waeren ein Fehler ohne
/// Fehlermeldung: die Kachel aktualisiert einfach nie.
enum WidgetKind {
    static let calories = "CaloriesRemaining"
    /// Seit 14.10.: Schritte als Ring und die grosse Kachel mit kcal und Schritten.
    static let steps = "StepsToday"
    static let today = "TodayOverview"
    /// Die kcal-Komplikation der Uhr (HealthyWatchWidget).
    static let watchKcal = "WatchKcal"
    static let focus = "FocusCountdown"
}
