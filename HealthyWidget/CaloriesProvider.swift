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

    /// Knapp, weil eine Erweiterung wenig Zeit bekommt - die zweihundert
    /// Sekunden aus dem APIClient sind fuer die Schnellerfassung gedacht.
    private let timeout: TimeInterval = 12

    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: Date(), state: .unreachable(nil))
    }

    // Das `@Sendable` ist nicht Kosmetik: das Protokoll verlangt
    // `@escaping @Sendable`, und ohne bricht der Build unter
    // SWIFT_STRICT_CONCURRENCY=complete ab, sobald man einen Task oeffnet.
    func getSnapshot(in context: Context,
                     completion: @escaping @Sendable (CaloriesEntry) -> Void) {
        Task { completion(CaloriesEntry(date: Date(), state: await state())) }
    }

    func getTimeline(in context: Context,
                     completion: @escaping @Sendable (Timeline<CaloriesEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = CaloriesEntry(date: now, state: await state())
            completion(Timeline(entries: [entry],
                                policy: .after(RemainingCalories.nextRefresh(after: now))))
        }
    }

    private func state() async -> WidgetState {
        guard let token = Keychain.read(Keychain.privateTokenKey), !token.isEmpty else {
            return .noAccess
        }
        let api = FoodAPI(cookie: "\(Keychain.privateTokenKey)=\(token)", timeout: timeout)
        do {
            let day = try await api.day(.today())
            let value = RemainingCalories(day: day)
            WidgetCache.save(value)
            return .value(value)
        } catch APIError.notAuthorised {
            // Token da, aber abgelehnt - fuer den Betrachter dasselbe wie kein
            // Zugang, und ein alter Stand waere hier irrefuehrend.
            return .noAccess
        } catch {
            return .unreachable(WidgetCache.load())
        }
    }
}
