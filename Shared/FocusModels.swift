import Foundation

/// Eine durchgestandene Fokus-Session, wie der Habits-Dienst sie liefert
/// (`/habits/api/focus/sessions`): ein Baum im Wald.
///
/// Anfang und Ende sind Zeitpunkte (`Instant`, ISO-8601 mit `Z`), nicht Tage -
/// `day` ist der Tag, dem der Dienst die Session zurechnet: der des Beginns,
/// in Felix' Zeitzone. Die App rechnet das nicht nach.
struct FocusSession: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let start: Date
    let end: Date
    let minutes: Int
    let day: CalendarDate
    /// Die Kategorie, vor dem Pflanzen gewaehlt - nil bei Baeumen ohne (alle
    /// vor dem 01.10.2026). Den Namen liefert der Dienst mit, auch den einer
    /// inzwischen geloeschten Kategorie.
    var categoryId: String? = nil
    var categoryName: String? = nil
}

/// Was die App meldet, wenn eine Session durch ist. Die Id vergibt die App,
/// damit ein Nachsenden aus dem Postausgang keinen zweiten Baum pflanzt.
struct FocusSessionDraft: Encodable, Sendable {
    let id: String
    let start: Date
    let end: Date
    /// Fehlt ohne Kategorie ganz - so sieht der Rumpf aus wie frueher.
    var categoryId: String? = nil
}

/// Eine Kategorie fuer die Baeume im Wald („Bachelorarbeit", „Uni") - Felix
/// vergibt die Namen selbst. Dieselbe Form liefert coHabit zur Auswahl fuer
/// Fokus-Habits, die nur nach einer Kategorie zaehlen.
struct FocusCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// Anlegen oder umbenennen - die Kennung vergibt der Dienst.
struct FocusCategoryDraft: Encodable, Sendable {
    let name: String
}

/// Welche Kategorie beim naechsten Pflanzen vorbelegt ist: die zuletzt
/// benutzte, je Geraet gemerkt - mit Namen, damit der Knopf ihn zeigt, bevor
/// die Liste geladen ist.
struct FocusCategoryMemory {

    static let key = "forest.category"

    var defaults: UserDefaults = .standard

    var lastUsed: FocusCategory? {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return nil }
            return try? JSONDecoder().decode(FocusCategory.self, from: data)
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }

    /// Die Vorbelegung aus dem, was zur Auswahl steht (nil: noch nie geladen
    /// - dann bleibt die gemerkte stehen). Umbenannt: der neue Name. Geloescht:
    /// keine, also „Ohne Kategorie".
    func preselection(from categories: [FocusCategory]?) -> FocusCategory? {
        guard let last = lastUsed else { return nil }
        guard let categories else { return last }
        return categories.first { $0.id == last.id }
    }
}

/// Die Kategorien eines Tages fuer die Zeile im Wald: „Bachelorarbeit 1:30 ·
/// Uni 0:30" - die meisten Minuten zuerst, Baeume ohne Kategorie als „Ohne
/// Kategorie", sobald es neben ihnen welche mit gibt. Ohne jede Kategorie
/// nil: die Zeile sieht dann aus wie frueher.
enum FocusCategoryBreakdown {
    static func text(_ sessions: [FocusSession]) -> String? {
        guard sessions.contains(where: { $0.categoryName != nil }) else { return nil }
        var minutes: [String: Int] = [:]
        var order: [String] = []
        for session in sessions {
            let name = session.categoryName ?? "Ohne Kategorie"
            if minutes[name] == nil { order.append(name) }
            minutes[name, default: 0] += session.minutes
        }
        // Gleich viele Minuten: wer zuerst gepflanzt wurde, steht vorn.
        return order.enumerated()
            .sorted { (-(minutes[$0.element] ?? 0), $0.offset) < (-(minutes[$1.element] ?? 0), $1.offset) }
            .map { "\($0.element) \(FocusMinutes.hours(minutes[$0.element] ?? 0))" }
            .joined(separator: " · ")
    }
}

/// Minuten als Stunden - „2:15 h", „2:15/4:00 h".
enum FocusMinutes {

    static func hours(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Der Stand von heute gegen das Tagesziel.
    static func progress(_ minutes: Int, goal: Int) -> String {
        "\(hours(minutes))/\(hours(goal)) h"
    }
}
