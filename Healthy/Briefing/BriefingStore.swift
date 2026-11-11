import Foundation

/// Das Morgen-Briefing im Dashboard (Vertrag §8.3, Felix 10.11.).
///
/// **Angefordert wird erst, wenn der Health-Abgleich dieses Oeffnens durch
/// ist** - mit oder ohne Erfolg (`ensure()` ruft das Dashboard danach). Sonst
/// schriebe die Sitzung den Text, bevor die Nacht von heute frueh beim Dienst
/// liegt. Eine Sperre nach Uhrzeit gibt es nicht: wer die Uhr nachts nicht
/// traegt, bekaeme sonst erst mittags ein Briefing.
///
/// Der Text von heute wird gemerkt (je Person), damit die Karte beim naechsten
/// Start sofort dasteht. Ohne Text fehlt sie.
@MainActor
@Observable
final class BriefingStore {

    private let api = BriefingAPI()

    /// Der Text von heute - `nil`: die Karte fehlt.
    private(set) var text: String?
    /// Ein neuer Text entsteht, der alte steht noch da - die Karte zeigt das
    /// mit einem kleinen Kreisel (nach dem Runterwischen dauert es 20 bis 40 s).
    private(set) var rewriting = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var ensuring = false
    /// Runterwischen, waehrend noch eine Anfrage ohne `refresh` unterwegs war
    /// (etwa nach einem Upload des Abgleichs): danach noch einmal mit.
    @ObservationIgnored private var refreshQueued = false
    /// Nachgefragt wird nur, solange das Dashboard zu sehen ist.
    @ObservationIgnored private var visible = false
    /// Ein Lauf ist unterwegs und noch nicht zu Ende abgewartet: verschwindet
    /// das Dashboard zwischendurch (anderer Tab, Recovery-Seite), geht das
    /// Nachfragen beim Wiederkommen weiter.
    @ObservationIgnored private var awaiting = false

    private static var memoryKey: String {
        "briefing.today" + HealthSyncScope.suffix(healthToken: Keychain.read(Keychain.healthTokenKey))
    }

    /// Ob der gemerkte Text schon gelesen ist. Nicht im `init`: den durchlaeuft
    /// SwiftUI bei jedem Neuaufbau der Ansicht, und der Schluessel haengt am
    /// Schluesselbund (je Person).
    @ObservationIgnored private var remembered = false

    init() {
        #if DEBUG
        if DashboardDemo.isOn {
            text = DashboardDemo.briefingText
            remembered = true
            // Fuer Bilder der Karte, waehrend ein neuer Text entsteht.
            rewriting = ProcessInfo.processInfo.environment["COCKPIT_BRIEFING_REWRITING"] == "1"
        }
        #endif
    }

    func appeared() {
        visible = true
        if Self.isDemo { return }
        let today = BriefingMemory.text(in: UserDefaults.standard.data(forKey: Self.memoryKey), today: .today())
        if !remembered {
            // Beim ersten Erscheinen: was fuer heute gemerkt ist, steht sofort da.
            remembered = true
            if text == nil { text = today }
        } else if text != nil, today == nil {
            // Der gemerkte Text von gestern ist kein Briefing mehr.
            text = nil
        }
        if awaiting { follow() }
    }

    func disappeared() {
        visible = false
        pollTask?.cancel()
        pollTask = nil
    }

    /// Fordert das Briefing von heute an - nach dem Abgleich dieses Oeffnens.
    ///
    /// - Parameters:
    ///   - enabled: was `/api/features` sagt; `false` heisst sicher
    ///     „nicht freigeschaltet“ - dann gar nicht erst fragen. `nil` (noch nicht
    ///     geladen, oder ein aelterer Dienst) fragt trotzdem: ein 403 oder 404
    ///     kostet nichts und blendet nur die Karte aus.
    ///   - refresh: Runterwischen - der Dienst schreibt den Text aus dem
    ///     aktuellen Stand neu (Felix, 11.11.).
    func ensure(enabled: Bool?, refresh: Bool = false) async {
        if Self.isDemo || Self.isTestHost { return }
        if enabled == false {
            forget()
            return
        }
        guard !ensuring else {
            if refresh { refreshQueued = true }
            return
        }
        ensuring = true
        defer { ensuring = false }
        var refresh = refresh
        repeat {
            refreshQueued = false
            await request(refresh: refresh)
            refresh = true
        } while refreshQueued
    }

    private func request(refresh: Bool) async {
        do {
            apply(try await api.ensure(refresh: refresh))
        } catch APIError.notAuthorised {
            // Nicht (mehr) freigeschaltet: auch der gemerkte Text geht.
            forget()
        } catch APIError.http(404, _) {
            forget()
        } catch {
            // Kein Netz, 503 ohne Text, alles andere: was dasteht, bleibt.
        }
    }

    private func apply(_ briefing: Briefing) {
        let shown = BriefingRule.text(shown: text, after: briefing)
        if shown != text { text = shown }
        if let shown, let data = BriefingMemory.data(text: shown, today: .today()) {
            UserDefaults.standard.set(data, forKey: Self.memoryKey)
        }
        awaiting = briefing.status == .running
        let rewritingNow = awaiting && shown != nil
        if rewriting != rewritingNow { rewriting = rewritingNow }
        if awaiting { follow() }
    }

    /// Fragt alle fuenf Sekunden nach, bis der Lauf durch ist - hoechstens zwei
    /// Minuten und nur, solange das Dashboard zu sehen ist.
    private func follow() {
        guard pollTask == nil, visible else { return }
        let api = api
        pollTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(BriefingRule.pollLimitSeconds)
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(BriefingRule.pollSeconds))
                // Abgebrochen (`disappeared`): wer abbricht, raeumt `pollTask`
                // selbst weg - hier nichts mehr anfassen.
                if Task.isCancelled { return }
                guard let briefing = try? await api.today() else { continue }
                if Task.isCancelled { return }
                guard let self else { return }
                if briefing.status != .running {
                    self.pollTask = nil
                    self.apply(briefing)
                    return
                }
            }
            if Task.isCancelled { return }
            // Zwei Minuten sind um: Schluss. Das naechste Oeffnen fragt neu an.
            self?.pollTask = nil
            self?.awaiting = false
            self?.rewriting = false
        }
    }

    private func forget() {
        text = nil
        rewriting = false
        awaiting = false
        pollTask?.cancel()
        pollTask = nil
        UserDefaults.standard.removeObject(forKey: Self.memoryKey)
    }

    private static var isDemo: Bool {
        #if DEBUG
        return DashboardDemo.isOn
        #else
        return false
        #endif
    }

    /// Die App als Wirt der Unit-Tests (`tools/verify.sh`): sie startet dabei
    /// ganz normal - und forderte bei jedem Lauf ein Briefing an, also eine
    /// Sitzung beim Dienst. Lesen darf sie, anfordern nicht.
    static let isTestHost =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
