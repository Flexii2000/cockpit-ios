import Foundation

/// Der letzte erfolgreich geholte Stand.
///
/// Liegt in `UserDefaults` der **Erweiterung** - deren eigener Behaelter, ohne
/// App-Group. Er ist ausdruecklich kein Ersatz fuer die Abfrage, sondern nur
/// das, was die Kachel zeigt, waehrend der Server nicht erreichbar ist. Und
/// er wird mit Datum gezeigt, nie als heutiger Rest ausgegeben.
enum WidgetCache {

    private static let key = "widget.calories.last"

    static func load() -> RemainingCalories? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? APIClient.decoder().decode(RemainingCalories.self, from: data)
    }

    static func save(_ value: RemainingCalories) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
