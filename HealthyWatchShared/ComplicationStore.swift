import Foundation

/// Was die Komplikationen auf der Uhr brauchen - im Schluesselbund der Uhr,
/// den Uhr-App und Komplikationen teilen (keine App-Gruppe, Entscheidung 12.10.).
///
/// Die Uhr-App legt ab, was das iPhone schickt (`WatchLink`); die Komplikationen
/// fragen selbst beim Kalorienzaehler (seit 20.11. die Ringe auch beim Weight
/// Tracker und bei Health) und fallen auf diesen Stand zurueck.
enum ComplicationStore {

    static let snapshotKey = "watch_complication"
    /// Der letzte Stand der Ringe-Komplikation (seit 20.11.).
    static let ringsKey = "watch_rings"

    /// Der Cookie-Kopf fuer den Kalorienzaehler: der persoenliche Token, sonst
    /// Felix' Privat-Token (`HealthCookie`), `nil` ohne Zugang.
    static func cookie() -> String? {
        HealthCookie.current()
    }

    /// Dasselbe fuer den Weight Tracker (Strain, Schrittziel): der persoenliche
    /// Token, sonst Felix' Weight-Token.
    static func weightCookie() -> String? {
        HealthCookie.currentWeight()
    }

    /// Was ein Kontext des iPhones an Zugang nennt.
    struct Tokens: Equatable, Sendable {
        var owner: String?
        var health: String?
        var weight: String?
        /// Der Kontext traegt die Marke `WatchKeys.accessVersion`: dann wird ein
        /// Privat- oder persoenlicher Token, der fehlt, geloescht. Ohne sie
        /// (aeltere iPhone-App) bleibt Fehlendes, wie es ist.
        var replacesAll: Bool
        /// Ebenso fuer den Weight-Token - erst ab Version 3 der Marke.
        var replacesWeight: Bool
    }

    /// Legt ab, was das iPhone an Zugang nennt.
    /// - Returns: ob sich etwas geaendert hat.
    @discardableResult
    static func save(_ access: Tokens) -> Bool {
        var changed = false
        let tokens = [(Keychain.privateTokenKey, access.owner, access.replacesAll),
                      (Keychain.healthTokenKey, access.health, access.replacesAll),
                      (Keychain.weightTokenKey, access.weight, access.replacesWeight)]
        for (key, value, replaces) in tokens {
            let stored = Keychain.read(key).flatMap { $0.isEmpty ? nil : $0 }
            if let value, !value.isEmpty {
                guard value != stored else { continue }
                Keychain.save(value, for: key)
                changed = true
            } else if replaces, stored != nil {
                Keychain.delete(key)
                changed = true
            }
        }
        return changed
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

    static func rings() -> RingsSnapshot? {
        guard let text = Keychain.read(ringsKey) else { return nil }
        return try? JSONDecoder().decode(RingsSnapshot.self, from: Data(text.utf8))
    }

    static func save(rings: RingsSnapshot) {
        guard rings != self.rings(), let data = try? JSONEncoder().encode(rings),
              let text = String(data: data, encoding: .utf8) else { return }
        Keychain.save(text, for: ringsKey)
    }

    /// Der Stand gehoerte der Person davor - weg damit, wenn der Zugang wechselt.
    static func clearSnapshot() {
        Keychain.delete(snapshotKey)
        Keychain.delete(ringsKey)
    }
}
