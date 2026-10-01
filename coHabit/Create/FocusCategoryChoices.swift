import Foundation

/// Die Kategorien aus dem Wald der Fokus-App zur Auswahl fuer ein Fokus-Habit
/// (`GET /focus/categories`). Nur Felix hat Baeume - alle anderen bekommen
/// eine leere Liste, und die Quelle Fokus-Zeit haben sie ohnehin nicht.
///
/// Fuer beide Formulare: Anlegen/Bearbeiten (`CohabitSettingsForm`) und das
/// alte der klassischen Liste (`ClassicEditorSheet`).
enum FocusCategoryChoices {

    /// Ohne Netz der letzte Stand, ohne den gar keiner - dann steht nur
    /// „Alle Bäume" zur Wahl.
    static func load(api: CohabitAPI) async -> [FocusCategory] {
        (try? await api.get("/focus/categories")) ?? []
    }

    /// Die Liste, dazu die Kategorie, die das Habit schon hat, falls sie im
    /// Wald inzwischen geloescht ist: der Dienst laesst sie einem bestehenden
    /// Habit, also darf das Formular sie nicht stillschweigend verlieren.
    static func merged(_ list: [FocusCategory], keeping id: String?, name: String?) -> [FocusCategory] {
        guard let id, !id.isEmpty, !list.contains(where: { $0.id == id }) else { return list }
        return list + [FocusCategory(id: id, name: name ?? "Kategorie")]
    }

    /// Wie weit sich die Minuten verstellen lassen: je Tag bis 16 Stunden in
    /// Viertelstunden (wie bisher), je Woche bis 168 Stunden in Stunden.
    static func range(weekly: Bool) -> ClosedRange<Int> {
        weekly ? 60...10_080 : 15...960
    }

    static func step(weekly: Bool) -> Int {
        weekly ? 60 : 15
    }

    /// „4:00 h am Tag", „10:00 h pro Woche".
    static func minutesText(_ minutes: Int, weekly: Bool) -> String {
        String(format: weekly ? "%d:%02d h pro Woche" : "%d:%02d h am Tag", minutes / 60, minutes % 60)
    }
}
