import WidgetKit

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

/// Holt den Tagesstand selbst.
///
/// Die Erweiterung ist ein eigener Prozess: sie sieht weder den Cookie-Speicher
/// der App noch deren Sitzung. Das Token kommt aus der geteilten
/// Keychain-Gruppe, der Cookie haengt selbst an der Anfrage.
struct CaloriesProvider: TimelineProvider {

    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: Date(), state: .unreachable(nil))
    }

    // Das `@Sendable` ist nicht Kosmetik: das Protokoll verlangt
    // `@escaping @Sendable`, und ohne bricht der Build unter
    // SWIFT_STRICT_CONCURRENCY=complete ab, sobald man einen Task oeffnet.
    func getSnapshot(in context: Context,
                     completion: @escaping @Sendable (CaloriesEntry) -> Void) {
        Task { completion(CaloriesEntry(date: Date(), state: await CaloriesSource.state())) }
    }

    func getTimeline(in context: Context,
                     completion: @escaping @Sendable (Timeline<CaloriesEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = CaloriesEntry(date: now, state: await CaloriesSource.state())
            completion(Timeline(entries: [entry],
                                policy: .after(RemainingCalories.nextRefresh(after: now))))
        }
    }

}

/// Der Tagesstand fuer jede Kachel mit kcal - die Kalorien-Kachel und seit
/// 14.10. die grosse Sperrbildschirm-Kachel mit Schritten.
enum CaloriesSource {

    /// Knapp, weil eine Erweiterung wenig Zeit bekommt - die zweihundert
    /// Sekunden aus dem APIClient sind fuer die Schnellerfassung gedacht.
    private static let timeout: TimeInterval = 12

    static func state() async -> WidgetState {
        guard let token = Keychain.read(Keychain.privateTokenKey), !token.isEmpty else {
            return .noAccess
        }
        let api = FoodAPI(cookie: "\(Keychain.privateTokenKey)=\(token)", timeout: timeout)
        do {
            let day = try await api.day(.today())
            // Was in der App noch wartet, zaehlt vorlaeufig mit - ueber den frisch
            // geholten Tag gelegt, damit schon Angekommenes nicht doppelt zaehlt.
            let pending = PendingFoodMirror.loadChanges()
            let shown = FoodOverlay.apply(pending, to: day)
            let value = RemainingCalories(day: shown, provisional: shown.entries != day.entries)
            WidgetCache.save(value)
            return .value(value)
        } catch APIError.notAuthorised {
            // Token da, aber abgelehnt - fuer den Betrachter dasselbe wie kein
            // Zugang, und ein alter Stand waere hier irrefuehrend.
            return .noAccess
        } catch {
            // Ohne Netz: was die App zuletzt fuer heute zeigte, wenn es neuer ist.
            let cached = WidgetCache.load()
            if let app = PendingFoodMirror.loadToday(), !app.isStale(),
               app.fetchedAt > (cached?.fetchedAt ?? .distantPast) {
                return .unreachable(app)
            }
            return .unreachable(cached)
        }
    }
}
