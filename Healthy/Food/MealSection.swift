import Foundation

/// Ein Abschnitt der Tagesliste. Eigener Typ und kein Tupel, weil `ForEach`
/// einen Schluesselpfad braucht - und den gibt es fuer Tupelfelder nicht.
struct MealSection: Identifiable, Sendable {
    let meal: Meal?
    let entries: [FoodEntry]

    var id: String { meal?.rawValue ?? "unassigned" }
    var label: String { meal?.label ?? "Ohne Zuordnung" }

    var total: Nutrients {
        entries.reduce(Nutrients.zero) { sum, entry in
            let part = entry.total
            return Nutrients(kcal: sum.kcal + part.kcal,
                             proteinG: sum.proteinG + part.proteinG,
                             carbsG: sum.carbsG + part.carbsG,
                             fatG: sum.fatG + part.fatG)
        }
    }
}
