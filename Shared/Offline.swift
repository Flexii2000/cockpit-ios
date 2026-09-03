import CryptoKit
import Foundation
import Observation

/// Was die App ohne Netz noch weiss.
///
/// Zwei Haelften, beide bewusst schlicht:
///
/// * **Lesen:** die letzte erfolgreiche Antwort jeder GET-Anfrage liegt als
///   Datei im Container. Bricht das Netz weg, wird sie gezeigt - mit Datum,
///   nie als aktueller Stand ausgegeben.
/// * **Schreiben:** ausgewaehlte Aenderungen (Haken, Gewicht, Essen) landen
///   in einem Postausgang und gehen raus, sobald wieder Netz da ist. Die App
///   rechnet dabei **nichts** nach: Straehnen, Tagessummen und Kacheln bleiben
///   Sache der Dienste. Bis der Ausgang leer ist, steht in der Leiste, wie
///   viele Aenderungen warten.
///
/// Das ist die eine Ausnahme von „kein Offline-Cache" (docs/ENTSCHEIDUNGEN.md):
/// ein Zwischenspeicher, kein zweiter Datenstand mit eigener Logik.
enum OfflineCache {

    /// Ob ein Fehler „kein Netz" heisst - und nicht „der Dienst hat Nein gesagt".
    ///
    /// Nur dann darf die Antwort aus dem Cache kommen: bei 403 oder 500 hat
    /// der Server geantwortet, und den alten Stand darueberzulegen hiesse,
    /// ein Problem zu verstecken.
    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .timedOut,
             .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    static func store(_ data: Data, for url: URL) {
        guard let file = file(for: url) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // Verschluesselt, solange das Geraet gesperrt ist: hier liegen auch
        // Noten und Kontostaende - nichts, was in einem Backup-Dump offen
        // stehen sollte. Gelesen wird ohnehin nur im Vordergrund.
        try? data.write(to: file, options: [.atomic, .completeFileProtection])
    }

    static func load(for url: URL) -> (data: Data, fetchedAt: Date)? {
        guard let file = file(for: url),
              let data = try? Data(contentsOf: file),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return (data, modified)
    }

    /// Beim Loeschen der Token: was ohne Zugang nicht mehr zu holen waere,
    /// soll auch nicht liegen bleiben.
    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Ablage

    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "OfflineCache")
    }

    /// Eine Datei je Adresse - mit Abfrageparametern, damit „30 Tage" und
    /// „3 Jahre" nicht dieselbe sind.
    static func file(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appending(path: name + ".json")
    }
}

/// Was in der Oberflaeche davon zu sehen ist.
@MainActor
@Observable
final class OfflineStatus {

    static let shared = OfflineStatus()

    /// Je Dienst: wann die gezeigten Daten geholt wurden, falls sie aus dem
    /// Cache kommen. Leer heisst: online.
    private(set) var staleSince: [Backend: Date] = [:]
    /// Aenderungen im Postausgang.
    private(set) var pending = 0
    /// Die letzte Aenderung, die der Dienst beim Nachsenden abgelehnt hat.
    private(set) var lastOutboxError: String?

    private init() {}

    func servedFromCache(_ backend: Backend, fetchedAt: Date) {
        staleSince[backend] = fetchedAt
    }

    func online(_ backend: Backend) {
        staleSince[backend] = nil
    }

    func outbox(pending: Int, lastError: String?) {
        self.pending = pending
        if let lastError { lastOutboxError = lastError }
        if pending == 0, lastError == nil { lastOutboxError = nil }
    }
}

/// Aenderungen, die auf Netz warten.
actor Outbox {

    static let shared = Outbox()

    struct Item: Codable, Sendable, Identifiable {
        let id: UUID
        let backend: String
        let url: String
        let method: String
        let body: Data?
        let createdAt: Date
    }

    private var items: [Item]
    private var isReplaying = false

    private static var file: URL? {
        OfflineCache.directory?.appending(path: "outbox.json")
    }

    private init() {
        if let file = Self.file, let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode([Item].self, from: data) {
            items = stored
        } else {
            items = []
        }
    }

    var count: Int { items.count }

    func enqueue(_ request: URLRequest, backend: Backend) async {
        guard let url = request.url?.absoluteString else { return }
        items.append(Item(id: UUID(), backend: backend.rawValue, url: url,
                          method: request.httpMethod ?? "POST",
                          body: request.httpBody, createdAt: Date()))
        persist()
        await OfflineStatus.shared.outbox(pending: items.count, lastError: nil)
    }

    /// Schickt der Reihe nach raus, was wartet.
    ///
    /// Haelt an, sobald wieder kein Netz ist oder der Dienst nicht antwortet -
    /// dann bleibt der Rest liegen. Lehnt der Dienst eine Aenderung ab (4xx),
    /// fliegt sie raus und der Grund steht in der Leiste: nochmal versuchen
    /// hiesse, dieselbe Ablehnung bei jedem Start zu kassieren.
    func replay() async {
        guard !isReplaying, !items.isEmpty else { return }
        isReplaying = true
        defer { isReplaying = false }
        var lastError: String?
        while let item = items.first, let url = URL(string: item.url) {
            var request = URLRequest(url: url)
            request.httpMethod = item.method
            request.httpBody = item.body
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if item.body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { break }
            if (200..<300).contains(status) {
                items.removeFirst()
            } else if (400..<500).contains(status) {
                lastError = "Nicht angenommen (HTTP \(status)): "
                    + (APIClient.shortMessage(from: data) ?? item.method + " " + url.path())
                items.removeFirst()
            } else {
                break
            }
            persist()
        }
        await OfflineStatus.shared.outbox(pending: items.count, lastError: lastError)
    }

    private func persist() {
        guard let file = Self.file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: file, options: [.atomic, .completeFileProtection])
        }
    }
}
