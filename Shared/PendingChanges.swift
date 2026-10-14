import Foundation
import Observation

/// Aenderungen, die die App sofort zeigt und spaeter schickt.
///
/// Angezeigt wird der letzte Stand des Dienstes und darueber, was hier wartet
/// (`TodoOverlay`, `ShoppingOverlay`). Geht eine Aenderung durch, ersetzt die
/// Antwort des Dienstes den Stand; lehnt er sie ab, fliegt sie hier raus - und
/// mit ihr verschwindet sie aus der Anzeige. Zurueckdrehen heisst also nur:
/// verwerfen und neu zeichnen. Dazu eine Meldung, die sagt, was nicht ging.
///
/// Anders als der alte `Outbox` (fertige `URLRequest`s, nur zum Nachsenden)
/// weiss diese Warteschlange, was eine Aenderung bedeutet: sie kann sie
/// anzeigen, zweimal Abhaken zusammenfassen, Unteraufgaben einer abgelehnten
/// Aufgabe mit verwerfen und in der Meldung den Namen nennen.
///
/// Je Dienst eine Spur: ein Kalorienzaehler, der nicht antwortet, haelt die
/// Einkaufsliste nicht auf. Innerhalb einer Spur geht alles der Reihe nach -
/// erst das Anlegen, dann der Haken darauf.
@MainActor
@Observable
final class PendingChanges {

    static let shared = PendingChanges()

    /// Wie eine Aenderung beim Dienst ankommt. Austauschbar fuer Tests.
    typealias Transport = @Sendable (Backend, PendingRequest) async -> DeliveryOutcome

    private(set) var entries: [PendingEntry] = []
    /// Je Dienst, was die Spur gerade tut - fuer die Leiste und die Uhr an der Zeile.
    private(set) var laneState: [Backend: LaneState] = [:]
    /// Die Aenderung, die gerade unterwegs ist - je Dienst hoechstens eine. Sie wird
    /// weder zusammengefasst noch verworfen, bis die Antwort da ist.
    private(set) var inFlight: [Backend: UUID] = [:]
    /// Die letzte Ablehnung je Dienst, bis jemand sie wegtippt.
    private(set) var lastRejection: [Backend: String] = [:]

    /// Nur im Vordergrund wird nach einem Fehlschlag von selbst erneut versucht.
    @ObservationIgnored var isForeground = true
    /// Wohin Meldungen gehen - die Apps haengen ihr Meldungsfenster an
    /// (`PendingSync`). Text und ob es nur ein Hinweis ist (grau statt rot).
    @ObservationIgnored var onNotice: ((String, Bool) -> Void)?
    /// Nach jeder Aenderung an dem, was wartet - Healthy reicht die wartenden
    /// Eintraege so an die Kalorien-Kachel weiter (`PendingFoodMirror`).
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let transport: Transport
    /// Ob `enqueue` gleich losschickt - Tests schicken selbst, Schritt fuer Schritt.
    @ObservationIgnored private let sendsImmediately: Bool
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var observers: [(backend: Backend, handler: (PendingEvent) -> Void)] = []
    @ObservationIgnored private var retryTasks: [Backend: Task<Void, Never>] = [:]
    @ObservationIgnored private var failures: [Backend: Int] = [:]
    @ObservationIgnored private var sequence = 0

    /// - Parameters:
    ///   - file: nur fuer Tests eine andere Datei, `nil` haelt alles im Speicher.
    ///   - transport: nur fuer Tests ein anderer Weg zum Dienst.
    ///   - sendsImmediately: nur fuer Tests `false`.
    init(file: URL? = PendingChanges.defaultFile, transport: @escaping Transport = PendingChanges.liveTransport,
         sendsImmediately: Bool = true) {
        self.file = file
        self.transport = transport
        self.sendsImmediately = sendsImmediately
        // Gleich hier, nicht erst beim ersten Zugriff aus einer Ansicht heraus: dort
        // waere das Einlesen eine Aenderung mitten im Zeichnen.
        load()
    }

    /// Nicht unter `OfflineCache.directory`: das wird beim Loeschen eines Tokens
    /// ganz geleert, und was wartet, gehoert nicht zum Zwischenspeicher.
    nonisolated static var defaultFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "Pending/changes.json")
    }

    /// 15 s statt der 30 der Apps: es geht im Hintergrund, und wer im Laden kein
    /// Netz hat, soll nicht eine halbe Minute auf den naechsten Versuch warten.
    nonisolated static let liveTransport: Transport = { backend, request in
        await APIClient(backend: backend, timeout: 15).deliver(request)
    }

    // MARK: - Lesen

    /// Was fuer diesen Dienst wartet, in der Reihenfolge, in der es entstand.
    func changes(for backend: Backend) -> [PendingChange] {
        load()
        return entries.filter { $0.change.backend == backend }.map(\.change)
    }

    func count(for backend: Backend) -> Int {
        load()
        return entries.filter { $0.change.backend == backend }.count
    }

    /// Ob an diesem Eintrag etwas wartet und die Spur gerade nicht sendet - die Uhr
    /// an der Zeile. Waehrend sie sendet, ist das meist eine Frage von Millisekunden,
    /// und eine aufblitzende Uhr waere nur Unruhe.
    func showsWaiting(_ id: String, on backend: Backend) -> Bool {
        let state = laneState[backend] ?? .idle
        guard state != .sending, state != .idle else { return false }
        return isWaiting(id, on: backend)
    }

    func isWaiting(_ id: String, on backend: Backend) -> Bool {
        load()
        return entries.contains { $0.change.backend == backend && $0.change.target == id }
    }

    /// Ob dieser Eintrag erst in der App existiert - der Dienst kennt ihn noch nicht.
    func isLocal(_ id: String, on backend: Backend) -> Bool {
        load()
        return entries.contains { $0.change.backend == backend && $0.change.role == .create && $0.change.target == id }
    }

    /// Zaehlt jede Anfrage durch - an Antworten und Abrufen. Ein Stand, der aelter ist
    /// als der gezeigte, darf ihn nicht ersetzen.
    func nextSequence() -> Int {
        sequence += 1
        return sequence
    }

    /// Ein Store meldet sich fuer seinen Dienst an: angekommene Antworten, Ablehnungen,
    /// leere Spur.
    func observe(_ backend: Backend, _ handler: @escaping (PendingEvent) -> Void) {
        observers.append((backend, handler))
    }

    // MARK: - Eintragen

    /// Nimmt eine Aenderung auf und schickt sie sofort los - die Anzeige hat sie schon.
    func enqueue(_ change: PendingChange, label: String) {
        load()
        let entry = PendingEntry(id: UUID(), change: change, label: label, createdAt: Date())
        var list = entries
        if PendingCoalescing.merge(&list, adding: entry, inFlight: inFlight[change.backend]) {
            list.append(entry)
        }
        entries = list
        lastRejection[change.backend] = nil
        persist()
        if sendsImmediately {
            Task { await replay(change.backend) }
        }
    }

    /// Beim Loeschen eines Tokens: was ohne Zugang nicht mehr ankaeme, verfaellt.
    func clear(_ backends: [Backend]) {
        load()
        entries.removeAll { backends.contains($0.change.backend) && inFlight[$0.change.backend] != $0.id }
        for backend in backends {
            lastRejection[backend] = nil
            laneState[backend] = .idle
        }
        persist()
    }

    func dismissRejection(_ backend: Backend) {
        lastRejection[backend] = nil
    }

    // MARK: - Senden

    func replayAll() async {
        load()
        let backends = Set(entries.map(\.change.backend))
        await withTaskGroup(of: Void.self) { group in
            for backend in backends {
                group.addTask { await self.replay(backend) }
            }
        }
    }

    /// Wieder im Vordergrund oder wieder Netz: die Wartezeiten von vorn.
    func resetBackoff() {
        for task in retryTasks.values { task.cancel() }
        retryTasks = [:]
        failures = [:]
    }

    /// Schickt der Reihe nach, was fuer diesen Dienst wartet. Ein Lauf je Dienst -
    /// kommt waehrenddessen etwas dazu, nimmt der laufende es mit.
    func replay(_ backend: Backend) async {
        load()
        guard inFlight[backend] == nil else { return }
        retryTasks[backend]?.cancel()
        retryTasks[backend] = nil
        var sentSomething = false
        while let entry = entries.first(where: { $0.change.backend == backend }) {
            inFlight[backend] = entry.id
            laneState[backend] = .sending
            let sequence = nextSequence()
            let outcome = await transport(backend, entry.change.request)
            inFlight[backend] = nil
            switch outcome {
            case .delivered(let data):
                finish(entry.id)
                failures[backend] = 0
                sentSomething = true
                if !data.isEmpty, let path = entry.change.boardPath {
                    // Neu gestartet ohne Netz soll die App zeigen, was schon angekommen
                    // ist - nicht den Stand von vor dem Senden.
                    OfflineCache.store(data, for: backend.url.appending(path: path))
                }
                notify(backend, .delivered(data, sequence: sequence))
            case .rejected(let status, let message):
                sentSomething = true
                if status == 404 && entry.change.request.notFoundMeansDone {
                    // Schon weg - das Ziel ist erreicht.
                    finish(entry.id)
                    continue
                }
                drop(entry)
                let notice = entry.change.notice(label: entry.label, status: status, message: message)
                if !notice.isInfo { lastRejection[backend] = notice.text }
                onNotice?(notice.text, notice.isInfo)
                notify(backend, .rejected)
            case .accessDenied:
                // Behalten: mit dem richtigen Token geht es spaeter durch. Neu versucht
                // wird beim naechsten Vordergrund, nicht im Takt.
                laneState[backend] = .accessDenied
                return
            case .offline, .serverDown:
                laneState[backend] = outcome == .offline ? .offline : .serverDown
                scheduleRetry(backend)
                return
            }
        }
        laneState[backend] = .idle
        if sentSomething { notify(backend, .drained) }
    }

    /// Wartet, bis gerade nichts fuer diesen Dienst unterwegs ist - hoechstens so lange.
    /// Ein Abruf, der neben einem Schreiben herlaeuft, holte sonst einen Stand ohne
    /// das gerade Geschriebene.
    func waitUntilIdle(_ backend: Backend, timeout: Duration) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while inFlight[backend] != nil, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Innereien

    private func finish(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Verwirft eine abgelehnte Aenderung und alles, was auf ihr aufbaut: die
    /// Unteraufgaben einer Aufgabe, die nicht angelegt wurde, und Haken darauf.
    private func drop(_ entry: PendingEntry) {
        var gone: Set<String> = []
        if entry.change.role == .create, let target = entry.change.target {
            gone.insert(target)
            for other in entries where other.change.backend == entry.change.backend && other.change.dependsOn == target {
                if let child = other.change.target { gone.insert(child) }
            }
        }
        entries.removeAll { other in
            other.id == entry.id
                || (other.change.backend == entry.change.backend
                    && (gone.contains(other.change.target ?? "") || gone.contains(other.change.dependsOn ?? "")))
        }
        persist()
    }

    private func notify(_ backend: Backend, _ event: PendingEvent) {
        for observer in observers where observer.backend == backend {
            observer.handler(event)
        }
    }

    /// Nach 5, 15, 30, 60 s, dann alle zwei Minuten - solange die App vorn ist.
    private func scheduleRetry(_ backend: Backend) {
        guard isForeground else { return }
        let count = (failures[backend] ?? 0) + 1
        failures[backend] = count
        let delays = [5, 15, 30, 60]
        let seconds = count <= delays.count ? delays[count - 1] : 120
        retryTasks[backend]?.cancel()
        retryTasks[backend] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.isForeground else { return }
            self.retryTasks[backend] = nil
            await self.replay(backend)
        }
    }

    // MARK: - Ablage

    private struct Stored: Codable {
        var version = 1
        var entries: [PendingEntry]
    }

    /// Liest die Datei, solange das noch nicht gelungen ist - wie der alte
    /// Postausgang: vor dem ersten Entsperren nach einem Neustart ist sie nicht
    /// lesbar, und ein leerer Stand duerfte sie dann nicht ueberschreiben.
    private func load() {
        guard !isLoaded else { return }
        guard let file else {
            isLoaded = true
            return
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            isLoaded = true
            return
        }
        guard let data = try? Data(contentsOf: file) else { return }
        let known: [PendingEntry]
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            known = stored.entries
        } else {
            // Kaputt: beiseitelegen statt still zu leeren, und sagen, dass etwas fehlt.
            let aside = file.deletingLastPathComponent()
                .appending(path: "changes-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            known = []
            onNotice?("Wartende Änderungen ließen sich nicht lesen.", false)
        }
        let ids = Set(known.map(\.id))
        let added = entries.filter { !ids.contains($0.id) }
        entries = known + added
        isLoaded = true
        if !added.isEmpty { persist() }
    }

    private func persist() {
        guard isLoaded, let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        defer { onChange?() }
        guard let data = try? JSONEncoder().encode(Stored(entries: entries)) else { return }
        // Erst nach dem ersten Entsperren lesbar, danach auch gesperrt: weckt
        // HealthKit Healthy im Hintergrund, soll das Nachsenden nicht an der Datei
        // scheitern. Darin stehen Einkaufs- und Aufgabentexte, keine Zugaenge.
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Was gesendet wird

/// Wie ein Dienst eine Aenderung beantwortet hat - danach eingeordnet, was die
/// Warteschlange damit tut.
enum DeliveryOutcome: Sendable, Equatable {
    /// Angekommen; die Antwort (bei To-Do und Einkauf das ganze Brett), leer bei 204.
    case delivered(Data)
    /// Der Dienst sagt Nein - mit seinem Grund, sofern er einen schickt.
    case rejected(status: Int, message: String?)
    /// Kein Zugang (401, 403 oder eine Anmeldeseite statt JSON): behalten.
    case accessDenied
    /// Kein Netz: behalten, spaeter noch einmal.
    case offline
    /// Der Dienst antwortet nicht (5xx) oder bittet um Geduld (408, 425, 429): behalten.
    case serverDown
}

/// Methode, Pfad und Rumpf einer Aenderung - der Pfad haengt an `Backend.url`.
struct PendingRequest: Sendable, Equatable {
    let method: String
    let path: String
    var body: Data?
    /// Loeschen: ist es schon weg (404), ist das Ziel erreicht.
    var notFoundMeansDone = false
}

enum LaneState: Sendable, Equatable {
    case idle, sending, offline, serverDown, accessDenied
}

/// Was ein Store von seiner Spur erfaehrt.
enum PendingEvent: Sendable {
    /// Eine Aenderung ist angekommen; die Antwort des Dienstes und die Nummer der Anfrage.
    case delivered(Data, sequence: Int)
    /// Der Dienst hat eine abgelehnt - der Stand darunter ist vielleicht ein anderer.
    case rejected
    /// Die Spur ist leer, nachdem sie etwas geschickt hat.
    case drained
}

struct PendingEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var change: PendingChange
    /// Was man in der Liste sieht („Milch“, „Rasen mähen“) - fuer die Meldung.
    var label: String
    let createdAt: Date
}

/// Was eine Aenderung tut - danach richtet sich das Zusammenfassen.
enum PendingRole: Sendable, Equatable {
    /// Legt etwas mit einer Kennung der App an.
    case create
    /// Setzt einen Zustand (abgehakt, erledigt) - der letzte gilt.
    case state
    /// Aendert Text und Felder - die letzte gilt.
    case edit
    case delete
    case other
}

/// Eine Aenderung, je Dienst ihre eigene Art.
enum PendingChange: Codable, Equatable, Sendable {
    case todo(TodoChange)
    case shopping(ShoppingChange)
    /// Ein Wert im Logbook (Weight Tracker, seit 12.10.).
    case logbook(LogbookChange)
    /// Ein Eintrag im Kalorienzaehler (Runde 4).
    case food(FoodChange)
    /// Ein Gewicht von Hand (Weight Tracker, Runde 4).
    case weight(WeightChange)
    /// Gym: Plan, Besuch oder Haken (Weight Tracker, seit 14.10.).
    case gym(GymChange)

    var backend: Backend {
        switch self {
        case .todo: .todo
        case .shopping: .shopping
        case .logbook, .weight, .gym: .weight
        case .food: .food
        }
    }

    var request: PendingRequest {
        switch self {
        case .todo(let change): change.request
        case .shopping(let change): change.request
        case .logbook(let change): change.request
        case .food(let change): change.request
        case .weight(let change): change.request
        case .gym(let change): change.request
        }
    }

    /// Die Kennung, die die Aenderung betrifft - beim Anlegen die neue.
    var target: String? {
        switch self {
        case .todo(let change): change.target
        case .shopping(let change): change.target
        case .logbook(let change): change.target
        case .food(let change): change.target
        case .weight(let change): change.target
        case .gym(let change): change.target
        }
    }

    var role: PendingRole {
        switch self {
        case .todo(let change): change.role
        case .shopping(let change): change.role
        case .logbook(let change): change.role
        case .food(let change): change.role
        case .weight(let change): change.role
        case .gym(let change): change.role
        }
    }

    /// Worauf eine Aenderung aufbaut - eine Unteraufgabe auf ihre Aufgabe.
    var dependsOn: String? {
        switch self {
        case .todo(let change): change.dependsOn
        case .shopping, .logbook, .food, .weight, .gym: nil
        }
    }

    /// Wohin die Antwort als Offline-Stand gehoert: To-Do und Einkauf antworten mit
    /// dem ganzen Brett. Logbook, Essen und Gewicht nur mit einem Tag bzw. der
    /// Zusammenfassung - das ist kein Stand einer festen Adresse und darf keinen
    /// ersetzen.
    var boardPath: String? {
        switch self {
        case .todo, .shopping: "/api/board"
        case .logbook, .food, .weight, .gym: nil
        }
    }

    var todo: TodoChange? {
        if case .todo(let change) = self { return change }
        return nil
    }

    var shopping: ShoppingChange? {
        if case .shopping(let change) = self { return change }
        return nil
    }

    var logbook: LogbookChange? {
        if case .logbook(let change) = self { return change }
        return nil
    }

    var food: FoodChange? {
        if case .food(let change) = self { return change }
        return nil
    }

    var weightEntry: WeightChange? {
        if case .weight(let change) = self { return change }
        return nil
    }

    var gym: GymChange? {
        if case .gym(let change) = self { return change }
        return nil
    }

    /// Ein wartendes Anlegen mit einer spaeteren Aenderung daran zusammengefasst.
    func folded(with edit: PendingChange) -> PendingChange? {
        switch (self, edit) {
        case (.todo(let create), .todo(let change)): create.folded(with: change).map(PendingChange.todo)
        case (.shopping(let create), .shopping(let change)): create.folded(with: change).map(PendingChange.shopping)
        case (.food(let create), .food(let change)): create.folded(with: change).map(PendingChange.food)
        default: nil
        }
    }

    func notice(label: String, status: Int, message: String?) -> PendingNotice {
        switch self {
        case .todo(let change): change.notice(label: label, status: status, message: message)
        case .shopping(let change): change.notice(label: label, status: status, message: message)
        case .logbook(let change): change.notice(label: label, status: status, message: message)
        case .food(let change): change.notice(label: label, status: status, message: message)
        case .weight(let change): change.notice(label: label, status: status, message: message)
        case .gym(let change): change.notice(label: label, status: status, message: message)
        }
    }
}

/// Eine Meldung zu einer abgelehnten Aenderung. Ein Hinweis (grau) statt eines
/// Fehlers, wenn das Ziel schlicht nicht mehr da ist - etwa ein Eintrag, den die
/// andere Person gerade geloescht hat.
struct PendingNotice: Sendable, Equatable {
    let text: String
    let isInfo: Bool

    /// „„Milch“ ließ sich nicht abhaken: <Grund>“ - der Grund, wie ihn der Dienst schickt.
    static func error(_ what: String, _ message: String?, status: Int) -> PendingNotice {
        PendingNotice(text: what + ": " + (message ?? "Der Dienst hat mit \(status) geantwortet."), isInfo: false)
    }
}

/// Fasst eine neue Aenderung mit wartenden zusammen. Liefert, ob sie noch angehaengt
/// werden muss. Was gerade unterwegs ist, bleibt unberuehrt.
enum PendingCoalescing {

    static func merge(_ entries: inout [PendingEntry], adding new: PendingEntry, inFlight: UUID?) -> Bool {
        let backend = new.change.backend
        guard let target = new.change.target else { return true }
        func waiting(_ entry: PendingEntry) -> Bool {
            entry.id != inFlight && entry.change.backend == backend
        }
        switch new.change.role {
        case .state:
            // Zweimal abhaken heisst: der letzte Stand gilt.
            entries.removeAll { waiting($0) && $0.change.role == .state && $0.change.target == target }
            return true
        case .edit:
            if let index = entries.firstIndex(where: { waiting($0) && $0.change.role == .create && $0.change.target == target }),
               let folded = entries[index].change.folded(with: new.change) {
                entries[index].change = folded
                entries[index].label = new.label
                return false
            }
            entries.removeAll { waiting($0) && $0.change.role == .edit && $0.change.target == target }
            return true
        case .delete:
            // Nur lokal angelegt und noch nicht unterwegs: dann geht gar nichts raus.
            let onlyLocal = entries.contains { waiting($0) && $0.change.role == .create && $0.change.target == target }
            // Was darauf aufbaut (Unteraufgaben), geht mit - auch wenn das Anlegen schon
            // unterwegs ist: der Dienst loescht sie mit ihr, ein spaeteres Anlegen liefe ins Leere.
            var gone: Set<String> = [target]
            for entry in entries where waiting(entry) && entry.change.dependsOn == target {
                if let child = entry.change.target { gone.insert(child) }
            }
            entries.removeAll { waiting($0) && (gone.contains($0.change.target ?? "") || gone.contains($0.change.dependsOn ?? "")) }
            return !onlyLocal
        case .create, .other:
            return true
        }
    }
}
