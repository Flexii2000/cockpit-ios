import Foundation

/// Freunde und Serien beim Weight Tracker. Siehe docs/BACKENDS.md und den
/// Vertrag `weight-app/docs/HEALTHY-CONTRACT.md` §10.
struct FriendsAPI: Sendable {

    private let client = APIClient(backend: .weight)

    func overview() async throws -> FriendsOverview {
        try await client.get("/api/friends")
    }

    /// Legt eine Einladung an - 409, wenn schon fuenf offen sind.
    func createInvite() async throws -> FriendInvite {
        try await client.send("POST", "/api/friends/invites")
    }

    /// Loest einen Code ein. 404 unbekannt oder abgelaufen, 400 der eigene,
    /// 409 schon befreundet, 429 nach zu vielen Fehlversuchen.
    func accept(code: String) async throws -> Friend {
        try await client.send("POST", "/api/friends", body: FriendAcceptRequest(code: code))
    }

    /// Beendet die Freundschaft fuer beide Seiten.
    func remove(id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/friends/\(id)")
    }

    /// 429 beim zweiten Stupser am selben Tag, 409 wenn drueben nichts mehr offen ist.
    func nudge(id: String) async throws -> NudgeResult {
        try await client.send("POST", "/api/friends/\(id)/nudge")
    }

    /// Die Serien-Kachel - auch ohne Freunde.
    func streaks() async throws -> StreakTile {
        try await client.get("/api/streaks")
    }
}
