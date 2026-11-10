import Foundation

/// Haelt, was der Freunde-Tab zeigt (Vertrag §10): die Freundschaften mit
/// ihren Serien, wie der Weight Tracker sie rechnet.
///
/// Geschrieben wird direkt, nie ueber die Warteschlange: einen Code einloesen
/// oder anstupsen will man jetzt wissen, nicht spaeter. Was nicht ging, steht
/// als Meldung oben (`NoticeCenter`).
@MainActor
@Observable
final class FriendsStore {

    private let api = FriendsAPI()

    private(set) var overview: FriendsOverview?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Der Dienst kennt die Freunde noch nicht (404) - der Tab bleibt leer,
    /// ohne Knoepfe, die ins Leere fuehrten.
    private(set) var missing = false
    private(set) var error: String?
    private(set) var accessProblem = false
    /// Freundschaften, deren Stupser gerade unterwegs ist.
    private(set) var nudging: Set<String> = []

    var friends: [Friend] { overview?.friends ?? [] }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        #if DEBUG
        if DashboardDemo.isOn {
            if overview == nil { overview = DashboardDemo.friendsOverview() }
            return
        }
        #endif
        do {
            overview = try await api.overview()
            missing = false
            error = nil
            accessProblem = false
        } catch APIError.notAuthorised {
            accessProblem = true
            error = "Kein Zugang zum Weight Tracker."
        } catch APIError.http(404, _) {
            missing = true
            error = nil
        } catch {
            accessProblem = false
            // Der letzte Stand bleibt stehen; nur ohne einen steht der Grund da.
            self.error = overview == nil ? FriendsFormat.message(error) : nil
        }
    }

    /// Der Code zum Teilen: ein noch offener wird wieder gezeigt, statt bei
    /// jedem Oeffnen einen neuen anzulegen (hoechstens fuenf sind offen).
    ///
    /// - Returns: `nil`, wenn es nicht ging - der Grund steht dann als Meldung da.
    func inviteCode() async -> String? {
        if Self.isDemo { return "K7Q4-M2XD" }
        if let open = overview?.invites.first?.code { return open }
        do {
            let invite = try await api.createInvite()
            overview?.invites.append(invite)
            return invite.code
        } catch {
            NoticeCenter.shared.show(FriendsFormat.inviteError(error))
            return nil
        }
    }

    /// Loest einen Code ein.
    ///
    /// - Returns: `nil`, wenn es geklappt hat - sonst, was unter dem Feld steht.
    func accept(code: String) async -> String? {
        if Self.isDemo { return nil }
        do {
            _ = try await api.accept(code: code)
            await load()
            return nil
        } catch {
            return FriendsFormat.acceptError(error)
        }
    }

    func remove(_ friend: Friend) async {
        if Self.isDemo {
            overview?.friends.removeAll { $0.id == friend.id }
            return
        }
        do {
            try await api.remove(id: friend.id)
            overview?.friends.removeAll { $0.id == friend.id }
        } catch APIError.http(404, _) {
            // Schon weg - die andere Seite war schneller.
            await load()
        } catch {
            NoticeCenter.shared.show(FriendsFormat.message(error))
        }
    }

    func nudge(_ friend: Friend) async {
        guard friend.nudge.allowed, !nudging.contains(friend.id) else { return }
        nudging.insert(friend.id)
        defer { nudging.remove(friend.id) }
        if Self.isDemo {
            setNudgeAllowed(false, for: friend.id)
            return
        }
        do {
            _ = try await api.nudge(id: friend.id)
            setNudgeAllowed(false, for: friend.id)
        } catch APIError.http(409, _) {
            // Drueben ist inzwischen nichts mehr offen: der Knopf geht still
            // aus, und der neue Stand kommt nach.
            setNudgeAllowed(false, for: friend.id)
            await load()
        } catch {
            if case APIError.http(429, _) = error { setNudgeAllowed(false, for: friend.id) }
            NoticeCenter.shared.show(FriendsFormat.nudgeError(error), isInfo: true)
        }
    }

    private func setNudgeAllowed(_ allowed: Bool, for id: String) {
        guard let index = overview?.friends.firstIndex(where: { $0.id == id }) else { return }
        overview?.friends[index].nudge.allowed = allowed
    }

    private static var isDemo: Bool {
        #if DEBUG
        return DashboardDemo.isOn
        #else
        return false
        #endif
    }
}
