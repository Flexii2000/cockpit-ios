import Foundation

/// Das Tagesziel des Waldes („2:15/4:00 h" bei „Heute").
///
/// Frueher kam es vom Habit „Fokus-Zeit"; seit die Habits nach coHabit
/// umgezogen sind, steht es dort im Co-Habit mit der Quelle FOCUS
/// (`config.auto.focusMinutesGoal`). Fokus fragt coHabit mit demselben
/// Privat-Cookie, mit dem es die Sessions meldet - fuer den Dienst ist das
/// Felix. Die Kennung des gefundenen Co-Habits wird gemerkt, damit es beim
/// naechsten Mal eine Anfrage ist statt einer Suche. Ohne ein solches
/// Co-Habit gibt es kein Ziel, wie frueher ohne das Habit.
///
/// Seit es Kategorien gibt (2026-10-01), taugt nur ein Fokus-Habit ueber
/// alle Baeume und je Tag als Tagesziel des Waldes: „1 h Bachelorarbeit"
/// oder „10 h pro Woche" gegen die Summe aller Baeume von heute zu stellen,
/// waere ein falscher Balken.
enum FocusGoal {

    private static let idKey = "forest.focusCohabitId"
    private static let goalKey = "forest.focusGoal"

    /// Das zuletzt gefundene Ziel - fuer den ersten Blick, bevor geladen ist.
    static var cached: Int? {
        UserDefaults.standard.object(forKey: goalKey) as? Int
    }

    static func load() async -> Int? {
        let client = APIClient(backend: .cohabit, timeout: 20)
        if let id = UserDefaults.standard.string(forKey: idKey),
           let goal = await goal(of: id, client: client) {
            remember(id: id, goal: goal)
            return goal
        }
        guard let list: [SummaryStub] = try? await client.get("/cohabits") else {
            // Ohne Antwort (kein Netz, kein Dienst) bleibt das alte Ziel stehen.
            return cached
        }
        // Automatische Co-Habits hakt man nicht selbst ab - nur die kommen in Frage.
        for stub in list where stub.ref.type == "STREAK" && !stub.canCheckIn {
            if let goal = await goal(of: stub.ref.id, client: client) {
                remember(id: stub.ref.id, goal: goal)
                return goal
            }
        }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: goalKey)
        return nil
    }

    private static func remember(id: String, goal: Int) {
        UserDefaults.standard.set(id, forKey: idKey)
        UserDefaults.standard.set(goal, forKey: goalKey)
    }

    private static func goal(of id: String, client: APIClient) async -> Int? {
        guard let detail: DetailStub = try? await client.get("/cohabits/\(id)"),
              let auto = detail.config.auto else { return nil }
        return dailyGoal(of: auto)
    }

    /// Das Tagesziel eines automatischen Co-Habits - nur Fokus ueber alle
    /// Baeume und je Tag.
    static func dailyGoal(of auto: Auto) -> Int? {
        guard auto.source == "FOCUS", auto.focusCategoryId == nil,
              (auto.focusPeriod ?? "DAY") == "DAY" else { return nil }
        return auto.focusMinutesGoal ?? 240
    }

    struct Auto: Decodable {
        let source: String
        let focusMinutesGoal: Int?
        var focusCategoryId: String? = nil
        var focusPeriod: String? = nil
    }

    // Nur die paar Felder, die hier zaehlen - die ganzen coHabit-Modelle
    // gehoeren in die coHabit-App, nicht nach Fokus.
    private struct SummaryStub: Decodable {
        struct Ref: Decodable {
            let id: String
            let type: String
        }
        let ref: Ref
        let canCheckIn: Bool
    }

    private struct DetailStub: Decodable {
        struct Config: Decodable {
            let auto: Auto?
        }
        let config: Config
    }
}
