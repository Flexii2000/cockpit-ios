import Foundation

/// Das Gym beim Weight Tracker (Vertrag `HEALTHY-CONTRACT.md` §6).
///
/// Geschrieben wird ueber die Warteschlange (`GymChange`) - jeder Schreibweg ist
/// ein PUT mit der Kennung der App. Hier steht nur, was Netz braucht: lesen und
/// loeschen.
struct GymAPI: Sendable {

    private let client = APIClient(backend: .weight)

    func state() async throws -> GymState {
        try await client.get("/api/gym")
    }

    func history(machineId: String) async throws -> [GymHistoryPoint] {
        try await client.get("/api/gym/history", query: [URLQueryItem(name: "machineId", value: machineId)])
    }

    func deleteDay(id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/gym/days/\(id)")
    }

    func deleteExercise(dayId: String, id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/gym/days/\(dayId)/exercises/\(id)")
    }
}
