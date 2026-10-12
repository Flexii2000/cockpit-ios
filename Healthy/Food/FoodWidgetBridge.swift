import WidgetKit

/// Reicht, was an Essen wartet, an die Kalorien-Kachel weiter (`PendingFoodMirror`):
/// nach jeder Aenderung an der Warteschlange, beim Start und wenn die App den Tag
/// von heute neu kennt. Die Kachel legt die wartenden Eintraege selbst ueber den
/// Tag, den sie holt - ohne Netz zeigt sie, was die App zuletzt fuer heute zeigte.
@MainActor
enum FoodWidgetBridge {

    static func start() {
        PendingChanges.shared.onChange = { changed() }
        changed()
    }

    /// Die Warteschlange hat sich geaendert.
    static func changed() {
        let changes = PendingChanges.shared.changes(for: .food).compactMap(\.food)
        guard PendingFoodMirror.saveChanges(changes) else { return }
        if changes.isEmpty { PendingFoodMirror.saveToday(nil) }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calories)
    }

    /// Der Tag von heute beim Dienst - und was die App daraus zeigt.
    static func today(server: DaySummary, known: [FoodEntry] = []) {
        guard server.date == .today() else { return }
        let changes = PendingChanges.shared.changes(for: .food).compactMap(\.food)
        let shown = FoodOverlay.apply(changes, to: server, known: known)
        let provisional = shown.entries != server.entries
        PendingFoodMirror.saveToday(provisional ? RemainingCalories(day: shown, provisional: true) : nil)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calories)
    }
}
