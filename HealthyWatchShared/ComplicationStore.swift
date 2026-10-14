import Foundation

/// Was die kcal-Komplikation auf der Uhr braucht - im Schluesselbund der Uhr,
/// den Uhr-App und Komplikation teilen (keine App-Gruppe, Entscheidung 12.10.).
///
/// Die Uhr-App legt ab, was das iPhone schickt (`WatchLink`); die Komplikation
/// fragt selbst beim Kalorienzaehler und faellt auf diesen Stand zurueck.
enum ComplicationStore {

    static let snapshotKey = "watch_complication"

    static func token() -> String? {
        Keychain.read(Keychain.privateTokenKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// - Returns: ob sich etwas geaendert hat.
    @discardableResult
    static func save(token: String) -> Bool {
        guard token != self.token() else { return false }
        Keychain.save(token, for: Keychain.privateTokenKey)
        return true
    }

    static func snapshot() -> ComplicationSnapshot? {
        guard let text = Keychain.read(snapshotKey) else { return nil }
        return try? JSONDecoder().decode(ComplicationSnapshot.self, from: Data(text.utf8))
    }

    /// Nur Neueres ersetzt - WatchConnectivity stellt aeltere Uebertragungen
    /// mitunter nach neueren zu.
    @discardableResult
    static func save(snapshot: ComplicationSnapshot) -> Bool {
        if let old = self.snapshot(), old.fetchedAt >= snapshot.fetchedAt { return false }
        guard let data = try? JSONEncoder().encode(snapshot), let text = String(data: data, encoding: .utf8)
        else { return false }
        Keychain.save(text, for: snapshotKey)
        return true
    }
}
