import CryptoKit
import Foundation

/// Was der Health-Abgleich sich merkt (Anker, Cursor der Rueckholung, der
/// Inhalt des letzten Naechte-Fensters), gilt je Person.
///
/// Mit Felix' Token bleiben die Schluessel, wie sie immer waren - sein iPhone
/// merkt von alledem nichts. Mit einem persoenlichen Token (seit 10.11.) haengt
/// ein kurzer Abdruck davon an: wechselt die Person, faengt die Rueckholung fuer
/// sie von vorn an, statt beim Cursor der Person davor weiterzumachen.
enum HealthSyncScope {

    /// Ob es ueberhaupt einen Zugang zum Weight Tracker gibt: der persoenliche
    /// Token oder Felix' eigener. Ohne einen von beiden fragt der Abgleich im
    /// Vordergrund weder Health noch den Dienst (`HealthSync.hasAccess`).
    static func hasAccess(healthToken: String?, weightToken: String?) -> Bool {
        healthToken?.isEmpty == false || weightToken?.isEmpty == false
    }

    /// - Returns: `""` ohne persoenlichen Token, sonst `.` und acht Hex-Zeichen.
    static func suffix(healthToken: String?) -> String {
        guard let healthToken, !healthToken.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(healthToken.utf8))
        return "." + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
