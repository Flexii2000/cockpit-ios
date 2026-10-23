import Foundation

/// Padel-Ergebnisse auf dem Weg zum Padel-Dienst (Felix, 23.10.). Die Uhr schickt selbst - mit
/// dem Token, den das iPhone ihr gibt - und zugleich uebers iPhone; der Dienst nimmt jede
/// Kennung nur einmal an. Was nicht ankommt, wartet hier auf den naechsten Versuch.
@MainActor
final class PadelReportOutbox {

    static let shared = PadelReportOutbox()

    private static let key = "padel.reports.pending"

    private(set) var pending: [PadelMatchReport]
    private var delivering = false

    private init() {
        pending = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? APIClient.decoder().decode([PadelMatchReport].self, from: $0) } ?? []
    }

    func add(_ report: PadelMatchReport) {
        guard !pending.contains(where: { $0.id == report.id }) else { return }
        pending.append(report)
        save()
    }

    /// Schickt, was wartet. Abgelehnt (4xx, etwa kein gueltiges Ergebnis) fliegt raus - noch
    /// einmal schicken hilft da nicht; ohne Netz oder Zugang bleibt es liegen.
    ///
    /// - Parameter cookie: auf der Uhr `fh_private=…` - sie hat keinen Cookie-Speicher, den
    ///   `Access` fuellt; auf dem iPhone `nil`.
    func deliver(cookie: String?) async {
        guard !delivering, !pending.isEmpty else { return }
        delivering = true
        defer { delivering = false }
        let client = APIClient(backend: .padel, cookie: cookie, timeout: 20)
        for report in pending {
            do {
                let _: APIClient.Empty = try await client.send("POST", "/api/results", body: report)
                remove(report.id)
            } catch APIError.http(let status, _) where (400..<500).contains(status) && ![408, 425, 429].contains(status) {
                remove(report.id)
            } catch {
                // Kein Netz, kein Zugang, Dienst weg: beim naechsten Mal.
            }
        }
    }

    private func remove(_ id: String) {
        pending.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? APIClient.encoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
