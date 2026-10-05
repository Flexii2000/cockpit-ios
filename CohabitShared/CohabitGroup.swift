import Foundation

/// Die App-Gruppe von coHabit und seiner Kachel.
///
/// Hier liegt, was beide Prozesse sehen muessen: der letzte Stand der Kachel
/// (die App legt ihn nach jedem Laden ab, die Kachel zeigt ihn, wenn sie
/// selbst nicht durchkommt), die Zeitzonen der Co-Habits (damit ein Haken aus
/// der Kachel ohne Netz den richtigen Tag bekommt) und der Postausgang.
enum CohabitGroup {

    static let identifier = "group.com.fherrmann.cohabit"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Der Ordner der Gruppe; ohne Gruppe (sollte nicht vorkommen) der eigene
    /// Behaelter - dann sieht die Kachel eben nichts davon.
    static var container: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static let widgetDataKey = "cohabit.widgetData"
    private static let zonesKey = "cohabit.zones"

    // MARK: - Stand der Kachel

    static func saveWidgetData(_ data: WidgetData) {
        guard let encoded = try? APIClient.encoder().encode(data) else { return }
        defaults.set(encoded, forKey: widgetDataKey)
    }

    static func loadWidgetData() -> WidgetData? {
        guard let data = defaults.data(forKey: widgetDataKey) else { return nil }
        return try? APIClient.decoder().decode(WidgetData.self, from: data)
    }

    // MARK: - Zeitzonen

    /// Merkt sich die Zone je Co-Habit - aus jedem geladenen Detail.
    static func remember(zone: String, for cohabitId: String) {
        var zones = defaults.dictionary(forKey: zonesKey) as? [String: String] ?? [:]
        guard zones[cohabitId] != zone else { return }
        zones[cohabitId] = zone
        defaults.set(zones, forKey: zonesKey)
    }

    static func zone(for cohabitId: String) -> TimeZone? {
        let zones = defaults.dictionary(forKey: zonesKey) as? [String: String] ?? [:]
        return zones[cohabitId].flatMap(TimeZone.init(identifier:))
    }

    /// Beim Abmelden: nichts von der vorigen Person soll liegen bleiben.
    static func clear() {
        defaults.removeObject(forKey: widgetDataKey)
        defaults.removeObject(forKey: zonesKey)
    }
}

/// Die Kennungen der Kacheln - `StaticConfiguration(kind:)` und
/// `reloadTimelines(ofKind:)` muessen dieselbe Zeichenkette sehen.
enum CohabitWidgetKind {
    /// Klein und rund auf dem Sperrbildschirm: ein gewaehltes Co-Habit.
    static let single = "CohabitSingle"
    /// Mittel: heute, alle Co-Habits.
    static let today = "CohabitToday"
    /// Gross: Challenge, Teamziel, offener Streak.
    static let board = "CohabitBoard"
    /// Rechteckig auf dem Sperrbildschirm: der Platz in der Challenge.
    static let challenge = "CohabitChallenge"
}
