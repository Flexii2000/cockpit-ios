import FamilyControls
import Foundation

/// Die Apps, die waehrend einer Session offen bleiben. Kommt aus Apples
/// Auswahlblatt (`FamilyActivityPicker`) und liegt als JSON in der
/// App-Gruppe - die Token darin sind absichtlich undurchsichtig, die App
/// erfaehrt nie, welche Apps das sind. In der Gruppe, weil auch die
/// Erweiterung sie braucht, wenn sie den Schild nach einem Neustart neu legt.
enum Whitelist {

    private static let key = "forest.whitelist"

    static func load() -> FamilyActivitySelection {
        // Frueher lag die Liste in den UserDefaults der App - einmal mitnehmen.
        let data = FocusHandoff.defaults.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
        guard let data,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func save(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            FocusHandoff.defaults.set(data, forKey: key)
        }
    }
}
