import Foundation

/// Die Endpunkte der klassischen Liste (`/classic/habits`, docs/BACKENDS.md) -
/// ueber denselben Client wie der Rest von coHabit: Bearer der Person,
/// Meldungen des Dienstes, letzter Stand ohne Netz.
struct ClassicAPI: Sendable {

    let api: CohabitAPI

    /// Streaks und Abstinenz der Person, auch geteilte, in Anlegereihenfolge.
    func list() async throws -> [ClassicHabit] {
        try await api.get("/classic/habits")
    }

    func create(_ draft: ClassicHabitDraft) async throws -> ClassicHabit {
        try await api.send("POST", "/classic/habits", body: draft)
    }

    /// Name, Ziele, Rhythmus - die Art nicht, und nur als Admin.
    func update(id: String, _ draft: ClassicHabitDraft) async throws -> ClassicHabit {
        try await api.send("PUT", "/classic/habits/\(id)", body: draft)
    }

    /// Allein: loeschen. Geteilt: verlassen - die anderen behalten es.
    func delete(id: String) async throws {
        try await api.sendIgnoringResponse("DELETE", "/classic/habits/\(id)")
    }

    /// Haken (Aufbauen) bzw. Rueckfall (Lassen) fuer einen Tag. Mit
    /// ausdruecklichem Datum, auch fuer heute: liegt er ohne Netz im
    /// Postausgang und geht erst morgen raus, waere „heute" dann falsch.
    func mark(id: String, _ request: ClassicMarkRequest) async throws -> ClassicHabit {
        try await api.send("POST", ClassicMarkRequest.path(habitId: id), body: request)
    }

    /// Nimmt den eigenen Eintrag des Tages zurueck; gibt es keinen, bleibt alles.
    func unmark(id: String, date: CalendarDate) async throws -> ClassicHabit {
        try await api.delete(ClassicMarkRequest.path(habitId: id, date: date))
    }
}
