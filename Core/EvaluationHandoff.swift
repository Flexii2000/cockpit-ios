import CryptoKit
import Foundation
import Security
import UserNotifications

/// Die Evaluation zieht von Healthy nach Fokus (Felix, 14.10.) - ohne dass eine
/// Antwort verloren geht.
///
/// Die Datei liegt im Container der App, und an den Container einer anderen App
/// kommt keine heran. Beide teilen aber die Schluesselbund-Gruppe
/// `com.fherrmann.shared`; durch die geht die Datei einmal hindurch. Eine
/// App-Gruppe waere der uebliche Weg, braucht fuer Healthy aber neue
/// Provisionierung - scheitert die, geht das Installieren schief (dieselbe
/// Abwaegung wie bei `PendingFoodMirror`, 12.10.).
///
/// Ablauf:
/// 1. **Healthy** legt die Bytes seiner Datei als Eintrag `evaluation_handoff`
///    ab (`offer`), liest ihn zurueck und vergleicht. Bei jedem Start erneut,
///    bis Fokus quittiert hat. Die eigene Datei **behaelt** Healthy - sie ist die
///    Sicherung, falls auf dem Weg etwas schiefgeht.
/// 2. **Fokus** prueft den Eintrag, schreibt ihn in seine Datei, liest zurueck,
///    quittiert mit dem SHA-256 der Bytes (`evaluation_imported`) und raeumt den
///    Eintrag weg (`EvaluationImport`).
///
/// Liegt hier und nicht in einer der Apps, weil beide Seiten dieselben
/// Schluessel und denselben Pfad brauchen.
enum EvaluationHandoff {

    static let handoffKey = "evaluation_handoff"
    static let importedKey = "evaluation_imported"
    static let reminderPrefix = "evaluation-"

    /// Wo die Datei liegt - in jeder App derselbe Pfad im eigenen Container.
    static var appFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Evaluation", isDirectory: true)
            .appendingPathComponent("evaluation.json")
    }

    /// Der Ablageort - im Betrieb der Schluesselbund, in Tests ein Woerterbuch.
    struct Slot: Sendable {
        var read: @Sendable (String) -> Data?
        var write: @Sendable (Data, String) -> Bool
        var delete: @Sendable (String) -> Void

        /// Nur entsperrt lesbar und nie im Backup - die Antworten sind privat,
        /// und keine Erweiterung braucht sie bei gesperrtem Geraet.
        static let keychain = Slot(
            read: { Keychain.readData($0) },
            write: { data, key in Keychain.saveData(data, for: key) == errSecSuccess },
            delete: { Keychain.delete($0) })
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Healthy

    enum Offer: Equatable, Sendable {
        /// Es gab nie eine Evaluation auf diesem iPhone.
        case noFile
        /// Die Datei ist da, aber gerade nicht lesbar (gesperrt) - spaeter noch einmal.
        case unreadable
        /// Fokus hat genau diesen Stand schon uebernommen.
        case alreadyImported
        case alreadyOffered
        case offered
        /// Schreiben oder Zuruecklesen ging schief - beim naechsten Start noch einmal.
        case failed
    }

    /// Healthy bietet seine Datei an. Laeuft bei jedem Start und Wechsel in den
    /// Vordergrund; kostet nach der Quittung nur noch einen Dateivergleich.
    @discardableResult
    static func offer(file: URL = appFile, slot: Slot = .keychain) -> Offer {
        guard FileManager.default.fileExists(atPath: file.path) else { return .noFile }
        guard let bytes = try? Data(contentsOf: file) else { return .unreadable }
        if let receipt = slot.read(importedKey), String(decoding: receipt, as: UTF8.self) == digest(bytes) {
            return .alreadyImported
        }
        if slot.read(handoffKey) == bytes { return .alreadyOffered }
        guard slot.write(bytes, handoffKey), slot.read(handoffKey) == bytes else { return .failed }
        return .offered
    }

    /// Healthy nimmt seine Erinnerungen um 21:30 zurueck - sie kommen jetzt aus
    /// Fokus, und ein Tipp darauf fuehrte in Healthy ins Leere.
    static func removeHealthyReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier).filter { $0.hasPrefix(reminderPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }
}
