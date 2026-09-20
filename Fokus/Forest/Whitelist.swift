import FamilyControls
import Foundation

/// Die Apps, die waehrend einer Session offen bleiben. Kommt aus Apples
/// Auswahlblatt (`FamilyActivityPicker`) und liegt als JSON in den
/// UserDefaults - die Token darin sind absichtlich undurchsichtig, die App
/// erfaehrt nie, welche Apps das sind.
enum Whitelist {

    private static let key = "forest.whitelist"

    static func load() -> FamilyActivitySelection {
        guard let data = UserDefaults.standard.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func save(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
