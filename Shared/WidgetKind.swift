import Foundation

/// Die Kennung der Kachel.
///
/// Steht hier, weil sie in `StaticConfiguration(kind:)` **und** in
/// `WidgetCenter.reloadTimelines(ofKind:)` identisch sein muss. Zwei
/// Zeichenketten, die auseinanderlaufen koennen, waeren ein Fehler ohne
/// Fehlermeldung: die Kachel aktualisiert einfach nie.
enum WidgetKind {
    static let calories = "CaloriesRemaining"
    static let habits = "HabitStreaks"
}
