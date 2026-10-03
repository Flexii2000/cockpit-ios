import Foundation

/// Eintraege, Nachrichten und Reaktionen, die auf Netz warten (Vertrag §5.1) -
/// und Haken und Rueckfaelle aus der klassischen Liste.
///
/// Anders als der `Outbox` der uebrigen Apps (rohe Anfragen, Cookie-Auth)
/// kennt dieser seine Arbeit: ein Haken mit Foto heisst erst das Foto
/// hochladen, dann den Eintrag mit dessen Kennung schicken. Und er liegt in
/// der App-Gruppe, weil auch der Abhak-Knopf der Kachel ohne Netz hier
/// ablegt. Doppelt entsteht nichts: Eintraege und Nachrichten tragen ihre
/// Kennung von der App, das Foto seinen Idempotenz-Schluessel.
///
/// Nachgerechnet wird nichts - bis der Postausgang leer ist, zeigt die App
/// den alten Stand und an der Stelle des Hakens eine Uhr.
actor CohabitOutbox {

    static let shared = CohabitOutbox()

    struct Entry: Codable, Sendable, Identifiable {
        enum Operation: Codable, Sendable {
            case checkin(cohabitId: String, request: CheckinRequest)
            case message(cohabitId: String, request: MessageRequest)
            case reaction(ReactionRequest, add: Bool)
            /// Haken bzw. Rueckfall aus der klassischen Liste.
            case classicMark(habitId: String, request: ClassicMarkRequest)
            /// Den eigenen Eintrag eines Tages zuruecknehmen - ein zweites Mal
            /// aendert nichts, deshalb braucht es keine Kennung.
            case classicUnmark(habitId: String, date: CalendarDate)
        }

        let id: UUID
        var operation: Operation
        /// Das Foto, das vorher hoch muss - Dateiname im Ordner des
        /// Postausgangs. Nach dem Hochladen weg, die Kennung steht dann in
        /// der Anfrage. Nur noch in Auftraegen der Fassung mit einem Foto.
        var photoFile: String?
        let createdAt: Date
        /// Die Fotos, die vorher hoch muessen, in Anzeige-Reihenfolge (ein
        /// Eintrag hat bis zu vier, Vertrag §2.3a). Jedes geht nach dem
        /// Hochladen hier raus und haengt sich an die Anfrage.
        var photoFiles: [String]?

        /// Was noch hochzuladen ist, der Reihe nach - auch aus einem alten Auftrag.
        var pendingPhotos: [String] { (photoFile.map { [$0] } ?? []) + (photoFiles ?? []) }
    }

    private let directory: URL
    private var isReplaying = false

    init(directory: URL = CohabitGroup.container.appending(path: "Outbox")) {
        self.directory = directory
    }

    private var file: URL { directory.appending(path: "outbox.json") }
    private var photos: URL { directory.appending(path: "photos") }

    // MARK: - Ablegen

    /// Legt einen Eintrag ab; die Fotos werden als Dateien daneben gelegt
    /// und gehen vor dem Eintrag hoch, in dieser Reihenfolge hinter die, deren
    /// Kennung die Anfrage schon traegt.
    func enqueueCheckin(cohabitId: String, request: CheckinRequest, photos: [Data]) async {
        await append(.checkin(cohabitId: cohabitId, request: request), photos: photos)
    }

    func enqueueCheckin(cohabitId: String, request: CheckinRequest, photo: Data?) async {
        await enqueueCheckin(cohabitId: cohabitId, request: request, photos: photo.map { [$0] } ?? [])
    }

    func enqueueMessage(cohabitId: String, request: MessageRequest, photo: Data?) async {
        await append(.message(cohabitId: cohabitId, request: request), photos: photo.map { [$0] } ?? [])
    }

    /// Haken oder Rueckfall aus der klassischen Liste - ohne Foto: mit
    /// Foto-Pflicht geht das Abhaken dort ueber das Beweisfoto-Blatt.
    func enqueueClassicMark(habitId: String, request: ClassicMarkRequest) async {
        await append(.classicMark(habitId: habitId, request: request), photos: [])
    }

    func enqueueClassicUnmark(habitId: String, date: CalendarDate) async {
        await append(.classicUnmark(habitId: habitId, date: date), photos: [])
    }

    /// Eine Reaktion - hebt eine wartende Gegenbewegung auf, statt beide zu
    /// schicken (zweimal tippen ohne Netz soll nichts bewegen).
    func enqueueReaction(_ request: ReactionRequest, add: Bool) async {
        var entries = load()
        if let index = entries.firstIndex(where: {
            if case .reaction(let other, let otherAdd) = $0.operation {
                return other == request && otherAdd != add
            }
            return false
        }) {
            entries.remove(at: index)
            save(entries)
            await publish(entries, error: nil)
            return
        }
        await append(.reaction(request, add: add), photos: [])
    }

    func entries() -> [Entry] { load() }

    func hasPending() -> Bool { !load().isEmpty }

    /// Beim Abmelden: alles weg, samt Fotos.
    func clear() async {
        try? FileManager.default.removeItem(at: directory)
        await publish([], error: nil)
    }

    /// Stand an die Oberflaeche melden - beim Start, damit die Uhr am Haken
    /// auch nach einem Neustart stimmt.
    func refreshStatus() async {
        await publish(load(), error: nil)
    }

    // MARK: - Nachsenden

    /// Schickt der Reihe nach, was wartet.
    ///
    /// Haelt an, sobald wieder kein Netz ist, der Dienst nicht antwortet (5xx)
    /// oder der Token nicht gilt - dann bleibt der Rest liegen. Lehnt der
    /// Dienst eine Aenderung ab (4xx), fliegt sie raus und der Grund steht in
    /// der Leiste: dieselbe Ablehnung bei jedem Start zu kassieren hilft
    /// niemandem. Ein 409 auf einen Haken heisst „schon erledigt" - das ist
    /// das Ziel, kein Fehler.
    func replay(using api: CohabitAPI = CohabitAPI()) async {
        guard !isReplaying else { return }
        isReplaying = true
        defer { isReplaying = false }
        var lastError: String?
        while var entry = load().first {
            do {
                // Jedes Foto einzeln: was oben ist, steht danach in der
                // Anfrage - ein Abbruch mittendrin laedt es nicht noch einmal.
                for photoFile in entry.pendingPhotos {
                    let data = try Data(contentsOf: photos.appending(path: photoFile))
                    let key = (photoFile as NSString).deletingPathExtension
                    let upload = try await api.uploadPhoto(jpeg: data, key: key)
                    entry.operation = entry.operation.withPhoto(upload.id)
                    if entry.photoFile == photoFile {
                        entry.photoFile = nil
                    } else {
                        entry.photoFiles?.removeAll { $0 == photoFile }
                    }
                    replaceFirst(with: entry)
                    try? FileManager.default.removeItem(at: photos.appending(path: photoFile))
                }
                try await send(entry.operation, api: api)
                removeFirst()
            } catch let error as CohabitError {
                switch error {
                case .offline, .unauthorized:
                    await publish(load(), error: lastError)
                    return
                case .server(let status, let message) where (400..<500).contains(status):
                    if status == 409, entry.operation.isEntry {
                        // schon erledigt - genau das sollte der Haken bewirken
                    } else {
                        lastError = entry.operation.rejection(message)
                    }
                    removeFirst(deletingPhotos: entry.pendingPhotos)
                default:
                    await publish(load(), error: lastError)
                    return
                }
            } catch {
                // Die Fotodatei ist weg - ohne sie laesst sich der Eintrag
                // nicht mehr vollstaendig schicken.
                lastError = "Ein wartendes Foto ließ sich nicht mehr lesen."
                removeFirst(deletingPhotos: entry.pendingPhotos)
            }
        }
        await publish([], error: lastError)
    }

    private func send(_ operation: Entry.Operation, api: CohabitAPI) async throws {
        switch operation {
        case .checkin(let cohabitId, let request):
            try await api.sendIgnoringResponse("POST", "/cohabits/\(cohabitId)/checkins", body: request)
        case .message(let cohabitId, let request):
            try await api.sendIgnoringResponse("POST", "/cohabits/\(cohabitId)/messages", body: request)
        case .reaction(let request, let add):
            if add {
                try await api.sendIgnoringResponse("POST", "/reactions", body: request)
            } else {
                let _: ReactionsResult = try await api.delete("/reactions", query: [
                    URLQueryItem(name: "target", value: request.target),
                    URLQueryItem(name: "reaction", value: request.reaction.rawValue),
                ])
            }
        case .classicMark(let habitId, let request):
            try await api.sendIgnoringResponse("POST", ClassicMarkRequest.path(habitId: habitId), body: request)
        case .classicUnmark(let habitId, let date):
            try await api.sendIgnoringResponse("DELETE", ClassicMarkRequest.path(habitId: habitId, date: date))
        }
    }

    // MARK: - Datei

    private func append(_ operation: Entry.Operation, photos images: [Data]) async {
        var entries = load()
        var photoFiles: [String] = []
        if !images.isEmpty {
            try? FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        }
        for image in images {
            // Der Dateiname ist der Idempotenz-Schluessel beim Hochladen.
            let name = UUID().uuidString.lowercased() + ".jpg"
            if (try? image.write(to: photos.appending(path: name), options: .atomic)) != nil {
                photoFiles.append(name)
            }
        }
        entries.append(Entry(id: UUID(), operation: operation, photoFile: nil, createdAt: Date(),
                             photoFiles: photoFiles.isEmpty ? nil : photoFiles))
        save(entries)
        await publish(entries, error: nil)
    }

    /// Immer frisch von der Platte: die Kachel ist ein zweiter Prozess und
    /// legt womoeglich gerade etwas dazu.
    private func load() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? APIClient.decoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        if let data = try? APIClient.encoder().encode(entries) {
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func replaceFirst(with entry: Entry) {
        var entries = load()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save(entries)
    }

    private func removeFirst(deletingPhotos photoFiles: [String] = []) {
        var entries = load()
        guard !entries.isEmpty else { return }
        entries.removeFirst()
        save(entries)
        for photoFile in photoFiles {
            try? FileManager.default.removeItem(at: photos.appending(path: photoFile))
        }
    }

    private func publish(_ entries: [Entry], error: String?) async {
        await CohabitSync.shared.update(from: entries, error: error)
    }
}

extension CohabitOutbox.Entry.Operation {
    /// Die Anfrage mit der Kennung des hochgeladenen Fotos - beim Eintrag
    /// hinten angehaengt, bei einer Nachricht das eine.
    func withPhoto(_ photoId: String) -> Self {
        switch self {
        case .checkin(let cohabitId, var request):
            request.appendPhoto(photoId)
            return .checkin(cohabitId: cohabitId, request: request)
        case .message(let cohabitId, var request):
            request.photoId = photoId
            return .message(cohabitId: cohabitId, request: request)
        case .reaction, .classicMark, .classicUnmark:
            return self
        }
    }

    /// Was in der Leiste steht, wenn der Dienst beim Nachsenden ablehnt. Ein
    /// Lauf nennt dazu Distanz und Dauer: abgelehnt ist er weg (meist die
    /// Pace), und ohne die Angaben wuesste man nicht mehr, was neu einzutragen ist.
    func rejection(_ message: String) -> String {
        if case .checkin(_, let request) = self, let run = request.runText {
            return "Lauf \(run) nicht angenommen: \(message)"
        }
        return "Nicht angenommen: \(message)"
    }

    /// Ein Eintrag fuer einen Tag - ein 409 darauf heisst „steht schon", also
    /// genau das, was er bewirken sollte.
    var isEntry: Bool {
        switch self {
        case .checkin, .classicMark: true
        case .message, .reaction, .classicUnmark: false
        }
    }
}
