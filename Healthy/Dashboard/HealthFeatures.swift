import Foundation

/// Was der Weight Tracker fuer diese Person freigeschaltet hat
/// (`GET /api/features`, Vertrag §8.1).
///
/// Nicht zu verwechseln mit `Features` des Kalorienzaehlers
/// (`/api/food/features`, Schnellerfassung). Fehlt ein Feld - ein Dienst von
/// vor der Funktion -, gilt sie als aus: lieber fehlt ein Knopf, als dass einer
/// ins Leere fuehrt.
struct HealthFeatures: Decodable, Equatable, Sendable {
    /// Wem der Zugang gehoert, mit dem gefragt wurde.
    var me: String?
    /// Der Chat mit der Claude-Instanz auf dem Server (§8.2).
    var chat = false
    /// Das Morgen-Briefing (§8.3) - haengt an derselben Freischaltung.
    var briefing = false
    var friends = false

    private enum CodingKeys: String, CodingKey {
        case me, chat, briefing, friends
    }

    init(me: String? = nil, chat: Bool = false, briefing: Bool = false, friends: Bool = false) {
        self.me = me
        self.chat = chat
        self.briefing = briefing
        self.friends = friends
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        me = try container.decodeIfPresent(String.self, forKey: .me)
        chat = try container.decodeIfPresent(Bool.self, forKey: .chat) ?? false
        briefing = try container.decodeIfPresent(Bool.self, forKey: .briefing) ?? false
        friends = try container.decodeIfPresent(Bool.self, forKey: .friends) ?? false
    }
}

struct HealthFeaturesAPI: Sendable {

    private let client = APIClient(backend: .weight)

    func get() async throws -> HealthFeatures {
        try await client.get("/api/features")
    }
}
