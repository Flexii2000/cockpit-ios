import Foundation

/// Der Cookie-Kopf fuer Kalorienzaehler und Weight Tracker dort, wo es keinen
/// gemeinsamen Cookie-Speicher gibt: in den Kacheln und auf der Uhr von Healthy.
///
/// Seit 10.11. kennt Healthy zwei Arten von Zugang: Felix' Privat-Token
/// (`fh_private`) und den persoenlichen Token einer Person (`health_token`).
/// Liegt der persoenliche vor, gilt er - dieselbe Reihenfolge wie im Dienst,
/// der ihn ebenfalls vor dem Privat-Cookie prueft.
enum HealthCookie {

    /// - Returns: `name=wert` fuer den `Cookie`-Kopf, oder `nil` ohne Zugang.
    static func header(health: String?, owner: String?) -> String? {
        if let health, !health.isEmpty { return "\(Keychain.healthTokenKey)=\(health)" }
        if let owner, !owner.isEmpty { return "\(Keychain.privateTokenKey)=\(owner)" }
        return nil
    }

    /// Aus dem Schluesselbund dieses Geraets (iPhone: geteilte Gruppe; Uhr: ihr eigener).
    static func current() -> String? {
        header(health: Keychain.read(Keychain.healthTokenKey),
               owner: Keychain.read(Keychain.privateTokenKey))
    }
}
