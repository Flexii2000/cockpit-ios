import WidgetKit

struct HabitsEntry: TimelineEntry {
    let date: Date
    let state: HabitsWidgetState
}

/// Holt die Liste selbst - wie `CaloriesProvider`, mit dem Token aus der
/// geteilten Keychain-Gruppe und dem Cookie an der Anfrage.
///
/// Ohne Netz liefert `APIClient` die letzte Antwort aus seinem Cache (der
/// Erweiterung eigener Container); `OfflineStatus` sagt dann, von wann sie
/// ist, und die Kachel schreibt das dazu.
struct HabitsProvider: TimelineProvider {

    private let timeout: TimeInterval = 12

    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: Date(), state: .unreachable)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping @Sendable (HabitsEntry) -> Void) {
        Task { completion(HabitsEntry(date: Date(), state: await state())) }
    }

    func getTimeline(in context: Context,
                     completion: @escaping @Sendable (Timeline<HabitsEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = HabitsEntry(date: now, state: await state())
            // Halbstuendlich plus Mitternacht: dann kippt "heute erledigt".
            completion(Timeline(entries: [entry],
                                policy: .after(RemainingCalories.nextRefresh(after: now))))
        }
    }

    private func state() async -> HabitsWidgetState {
        guard let token = Keychain.read(Keychain.privateTokenKey), !token.isEmpty else {
            return .noAccess
        }
        let api = HabitsAPI(cookie: "\(Keychain.privateTokenKey)=\(token)", timeout: timeout)
        do {
            let habits = try await api.list()
            let stale = await MainActor.run { OfflineStatus.shared.staleSince[.habits] }
            return .value(habits, staleSince: stale)
        } catch APIError.notAuthorised {
            return .noAccess
        } catch {
            return .unreachable
        }
    }
}
