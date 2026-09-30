import Foundation

/// Was „Heute" zeigt (`GET /today`, Vertrag §3.7).
@MainActor
@Observable
final class TodayStore {

    private(set) var today: Today?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    /// Stupser, die schon beantwortet oder weggewischt sind - bis zum
    /// naechsten Laden nicht mehr zeigen.
    private(set) var hiddenNudges: Set<String> = []

    var nudges: [Nudge] {
        (today?.nudges ?? []).filter { !hiddenNudges.contains($0.id) }
    }

    func load() async {
        isLoading = today == nil
        defer { isLoading = false }
        do {
            today = try await Session.shared.api().get("/today")
            errorMessage = nil
            hiddenNudges = []
            WidgetSync.refreshSoon()
        } catch {
            if await Session.shared.handle(error) { return }
            // Ohne Netz und ohne alten Stand bleibt nur der Hinweis.
            errorMessage = error.localizedDescription
        }
    }

    /// „Zurückstupsen": stupst den Absender im selben Co-Habit (Vertrag §2.7).
    func nudgeBack(_ nudge: Nudge) async {
        hiddenNudges.insert(nudge.id)
        let api = Session.shared.api()
        do {
            try await api.sendIgnoringResponse("POST", "/cohabits/\(nudge.cohabit.id)/nudges",
                                               body: NudgeRequest(to: nudge.from.id, text: nil))
            Toast.shared.show("\(nudge.from.displayName) angestupst")
        } catch {
            Toast.shared.show(error)
        }
        try? await api.sendIgnoringResponse("POST", "/nudges/\(nudge.id)/seen")
    }

    func hide(_ nudge: Nudge) async {
        hiddenNudges.insert(nudge.id)
        try? await Session.shared.api().sendIgnoringResponse("POST", "/nudges/\(nudge.id)/seen")
    }
}

struct NudgeRequest: Encodable {
    let to: String
    let text: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(to, forKey: .to)
        try c.encode(text, forKey: .text)
    }

    private enum CodingKeys: String, CodingKey { case to, text }
}
