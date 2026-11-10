import Foundation

/// Der Chat mit der Claude-Instanz auf dem Heimserver (Vertrag §8.2, Felix
/// 10.11.).
///
/// Gehoert dem Dashboard und nicht dem Blatt: eine Antwort, die noch laeuft,
/// soll weiterlaufen, wenn das Blatt zugeht - und der Knopf im Dashboard zeigt,
/// wenn sie da ist. Das Gespraech liegt beim Dienst; hier steht nur, was er
/// liefert, dazu Fragen, die noch unterwegs sind.
@MainActor
@Observable
final class ChatStore {

    private let api = ChatAPI()

    private(set) var exchanges: [ChatExchange] = []
    /// Fragen, die abgeschickt sind und die der Dienst noch nicht kennt.
    private(set) var sending: [ChatPendingSend] = []
    private(set) var limits: ChatLimits?
    private(set) var hasLoaded = false
    /// Eine Frage, die der Dienst nicht angenommen hat - sie geht zurueck ins
    /// Eingabefeld, statt verloren zu sein.
    var returnedDraft: String?

    /// Bis zu welcher Antwort der Chat offen war - je Person gemerkt.
    private var seenThrough: Date?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var loading = false

    /// Der Chat steht offen: dann ist gesehen, was ankommt, und die Meldung
    /// „Deine Antwort ist da.“ braucht kein Banner.
    var isVisible = false {
        didSet {
            ChatPresence.shared.set(isVisible)
            if isVisible { markSeen() }
        }
    }

    private static var seenKey: String {
        "chat.seenThrough" + HealthSyncScope.suffix(healthToken: Keychain.read(Keychain.healthTokenKey))
    }

    /// Ob `seenThrough` schon gelesen ist. Nicht im `init`: den durchlaeuft
    /// SwiftUI bei jedem Neuaufbau der Ansicht, und der Schluessel haengt am
    /// Schluesselbund (je Person). Vor dem ersten Laden gibt es ohnehin keine
    /// Antwort, die ungesehen sein koennte.
    @ObservationIgnored private var seenLoaded = false

    init() {
        #if DEBUG
        if DashboardDemo.isOn {
            exchanges = DashboardDemo.chatExchanges()
            limits = ChatLimits(perDay: 30, usedToday: exchanges.count, maxChars: 1000)
            hasLoaded = true
            seenThrough = ChatTimeline.latestAnswer(exchanges)
            seenLoaded = true
        }
        #endif
    }

    private func loadSeenIfNeeded() {
        guard !seenLoaded else { return }
        seenLoaded = true
        let stored = UserDefaults.standard.double(forKey: Self.seenKey)
        seenThrough = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    var bubbles: [ChatBubble] { ChatTimeline.bubbles(exchanges: exchanges, sending: sending) }

    /// Eine Antwort laeuft oder eine Frage ist unterwegs - solange ist das
    /// Senden aus (der Dienst naehme eine zweite ohnehin nicht an).
    var isBusy: Bool {
        exchanges.contains { $0.status == .running } || sending.contains { $0.failure == nil }
    }

    var maxChars: Int { limits?.maxChars ?? 1000 }

    /// Der Knopf im Dashboard ist gefuellt, solange eine Antwort ungesehen ist.
    var hasUnseenAnswer: Bool {
        !isVisible && ChatTimeline.hasUnseenAnswer(exchanges, seenThrough: seenThrough)
    }

    // MARK: - Laden

    func load() async {
        guard !Self.isDemo, !loading else { return }
        loading = true
        defer { loading = false }
        guard let state = try? await api.state() else { return }
        take(state)
    }

    private func take(_ state: ChatState) {
        loadSeenIfNeeded()
        exchanges = state.exchanges
        limits = state.limits
        hasLoaded = true
        // Was der Dienst inzwischen kennt, ist nicht mehr unterwegs.
        let known = Set(state.exchanges.map(\.id))
        sending.removeAll { known.contains($0.id) }
        if isVisible { markSeen() }
        if exchanges.contains(where: { $0.status == .running }) { follow() }
    }

    private func markSeen() {
        loadSeenIfNeeded()
        guard let latest = ChatTimeline.latestAnswer(exchanges), latest != seenThrough else { return }
        seenThrough = latest
        if !Self.isDemo {
            UserDefaults.standard.set(latest.timeIntervalSince1970, forKey: Self.seenKey)
        }
    }

    /// Fragt nach, bis keine Antwort mehr laeuft: 1,5 s in den ersten 30
    /// Sekunden, dann alle 3 s, hoechstens fuenf Minuten (Vertrag §8.2).
    private func follow() {
        guard pollTask == nil else { return }
        let api = api
        let started = Date()
        pollTask = Task { [weak self] in
            while let delay = ChatTimeline.pollDelay(elapsed: Date().timeIntervalSince(started)) {
                try? await Task.sleep(for: .seconds(delay))
                // Abgebrochen („Neuer Chat“): wer abbricht, raeumt `pollTask`
                // selbst weg - und was jetzt noch kaeme, ist der alte Stand.
                if Task.isCancelled { return }
                guard let state = try? await api.state() else { continue }
                if Task.isCancelled { return }
                guard let self else { return }
                if !state.exchanges.contains(where: { $0.status == .running }) {
                    self.pollTask = nil
                    self.take(state)
                    return
                }
                self.take(state)
            }
            if Task.isCancelled { return }
            self?.pollTask = nil
        }
    }

    // MARK: - Fragen

    /// Stellt eine Frage. Sie steht sofort da; nimmt der Dienst sie nicht an
    /// (eine Antwort laeuft noch, Tageslimit, Agent nicht erreichbar), geht sie
    /// mit einer Meldung zurueck ins Eingabefeld.
    func send(_ input: String) {
        guard let text = ChatTimeline.question(from: input), !isBusy else { return }
        guard text.count <= maxChars else {
            NoticeCenter.shared.show("Höchstens \(GermanNumber.string(Double(maxChars))) Zeichen.")
            returnedDraft = text
            return
        }
        post(ChatPendingSend(id: ChatTimeline.newID(), text: text))
    }

    /// Noch einmal: was nie ankam, mit derselben Kennung; was beim Dienst
    /// gescheitert ist, als neue Frage.
    func retry(_ retry: ChatRetry) {
        guard !isBusy else { return }
        switch retry {
        case .resend(let pending):
            post(ChatPendingSend(id: pending.id, text: pending.text))
        case .askAgain(let question):
            post(ChatPendingSend(id: ChatTimeline.newID(), text: question))
        }
    }

    private func post(_ pending: ChatPendingSend) {
        sending.removeAll { $0.id == pending.id }
        sending.append(pending)
        if Self.isDemo { return }
        let api = api
        Task { [weak self] in
            // Im Zusammenhang fragen: die Antwort kann eine halbe Minute
            // dauern, und kommt sie bei geschlossener App, meldet sie sich.
            await Notifications.requestPermission()
            do {
                let exchange = try await api.ask(ChatSend(id: pending.id, text: pending.text))
                self?.accepted(exchange)
            } catch {
                self?.failed(pending, error)
            }
        }
    }

    private func accepted(_ exchange: ChatExchange) {
        loadSeenIfNeeded()
        sending.removeAll { $0.id == exchange.id }
        if let index = exchanges.firstIndex(where: { $0.id == exchange.id }) {
            exchanges[index] = exchange
        } else {
            exchanges.append(exchange)
        }
        if isVisible { markSeen() }
        if exchange.status == .running { follow() }
    }

    private func failed(_ pending: ChatPendingSend, _ error: Error) {
        if let rejection = ChatTimeline.rejection(error) {
            // Der Dienst hat geantwortet und Nein gesagt: die Frage steht nicht
            // im Gespraech - zurueck ins Feld damit.
            sending.removeAll { $0.id == pending.id }
            returnedDraft = pending.text
            NoticeCenter.shared.show(rejection, isInfo: true)
            return
        }
        // Nicht angekommen (kein Netz, Zeitueberschreitung): die Blase bleibt
        // und laesst sich antippen.
        if let index = sending.firstIndex(where: { $0.id == pending.id }) {
            sending[index].failure = ChatTimeline.failure(error)
        }
    }

    /// „Neuer Chat“: beim Dienst ist danach alles weg, eine laufende Antwort
    /// wird verworfen.
    func reset() async {
        pollTask?.cancel()
        pollTask = nil
        if Self.isDemo {
            exchanges = []
            sending = []
            return
        }
        do {
            try await api.reset()
            exchanges = []
            sending = []
        } catch {
            NoticeCenter.shared.show(ChatTimeline.message(error))
        }
    }

    private static var isDemo: Bool {
        #if DEBUG
        return DashboardDemo.isOn
        #else
        return false
        #endif
    }
}
