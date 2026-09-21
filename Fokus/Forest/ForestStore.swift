import FamilyControls
import Foundation
import UserNotifications

/// Haelt den Wald und fuehrt eine Session von „pflanzen" bis „steht".
///
/// Die Sessions liegen beim Habits-Dienst - derselbe Bestand, aus dem das
/// Habit „Fokus-Zeit" rechnet. Die App merkt sich nur zweierlei selbst: die
/// **laufende** Session (in den UserDefaults, damit sie einen Neustart
/// uebersteht) und fertige Sessions, die der Dienst **noch nicht bestaetigt**
/// hat - der Baum steht sofort, auch ohne Netz.
@MainActor
@Observable
final class ForestStore {

    private let api = HabitsAPI()
    private let screenTime = ScreenTimeGuard()

    /// Der Baum, der gerade waechst. Nil, wenn keine Session laeuft.
    private(set) var active: ActiveSession?
    /// Was der Dienst kennt, neueste zuerst.
    private(set) var sessions: [FocusSession] = []
    /// Fertig, aber noch nicht beim Dienst angekommen (Postausgang oder
    /// abgelehnt); wird beim naechsten Laden nachgereicht.
    private(set) var unsynced: [FocusSession] = []
    /// Das Habit „Fokus-Zeit", falls es eins gibt - fuer das Tagesziel.
    private(set) var focusHabit: HabitStatus?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isAccessProblem = false

    var whitelist: FamilyActivitySelection {
        didSet { Whitelist.save(whitelist) }
    }
    /// Stand der Erlaubnis „Bildschirmzeit" - nach jedem Nachfragen und jedem
    /// Laden neu gelesen, weil sich `AuthorizationCenter` nicht beobachten
    /// laesst. Nil heisst: alles gut, nichts anzuzeigen.
    private(set) var screenTimeNote: String?
    var shortcutsEnabled: Bool {
        didSet { ShortcutsBridge.isEnabled = shortcutsEnabled }
    }

    /// Welcher Ausschnitt gezeigt wird - gemerkt, damit die Wahl bleibt.
    var range: ForestRange {
        didSet { UserDefaults.standard.set(range.rawValue, forKey: Self.rangeKey) }
    }

    /// So weit reicht der Wald zurueck: ein Jahr, der groesste Ausschnitt.
    static let historyDays = 365

    private static let activeKey = "forest.active"
    private static let unsyncedKey = "forest.unsynced"
    private static let rangeKey = "forest.range"
    private var endWatcher: Task<Void, Never>?

    init() {
        whitelist = Whitelist.load()
        shortcutsEnabled = ShortcutsBridge.isEnabled
        range = UserDefaults.standard.string(forKey: Self.rangeKey).flatMap(ForestRange.init) ?? .week
        #if DEBUG
        // Fuer Bilder jedes Ausschnitts - tippen kann der Simulator nicht.
        if let raw = ProcessInfo.processInfo.environment["COCKPIT_FOREST_RANGE"],
           let forced = ForestRange(rawValue: raw) {
            range = forced
        }
        #endif
        active = Self.read(ActiveSession.self, key: Self.activeKey)
        unsynced = Self.read([FocusSession].self, key: Self.unsyncedKey) ?? []
        #if DEBUG
        // Nur fuers Bild: eine Session, die vor zehn Minuten begann. Ohne
        // Schild - im Simulator gibt es keinen - und ohne Baum am Ende.
        if active == nil,
           let raw = ProcessInfo.processInfo.environment["COCKPIT_FOREST_RUNNING"],
           let minutes = Int(raw) {
            active = ActiveSession(id: "demo",
                                   start: Date().addingTimeInterval(-600),
                                   end: Date().addingTimeInterval(Double(minutes) * 60),
                                   shielded: true, test: true)
        }
        #endif
        watchEnd()
    }

    /// Alle Baeume: was der Dienst kennt plus das, was lokal noch wartet.
    var allSessions: [FocusSession] {
        let known = Set(sessions.map(\.id))
        return sessions + unsynced.filter { !known.contains($0.id) }
    }

    /// Die Baeume im gewaehlten Ausschnitt.
    var visibleSessions: [FocusSession] {
        let today = CalendarDate.today()
        return allSessions.filter { range.contains($0.day, today: today) }
    }

    /// Der Ausschnitt als Tage, neueste zuerst.
    var visibleDays: [ForestDay] {
        ForestDay.group(visibleSessions)
    }

    var visibleMinutes: Int {
        visibleSessions.reduce(0) { $0 + $1.minutes }
    }

    var todayMinutes: Int {
        let today = CalendarDate.today()
        return allSessions.filter { $0.day == today }.reduce(0) { $0 + $1.minutes }
    }

    /// Das Tagesziel aus dem Habit „Fokus-Zeit" - ohne Habit kein Ziel.
    var dailyGoal: Int? {
        focusHabit?.focusMinutesGoal ?? focusHabit?.progress?.goal
    }

    func load() async {
        isLoading = sessions.isEmpty
        screenTimeNote = screenTime.note
        defer { isLoading = false }
        let today = CalendarDate.today()
        let calendar = Calendar(identifier: .gregorian)
        let fromDate = calendar.date(byAdding: .day, value: -Self.historyDays, to: today.startOfDay())
            ?? today.startOfDay()
        do {
            async let list = api.focusSessions(from: CalendarDate(date: fromDate), to: today)
            async let habits = api.list()
            sessions = try await list
            focusHabit = (try? await habits)?.first { $0.kind == .focus }
            errorMessage = nil
            isAccessProblem = false
            await syncPending()
        } catch {
            report(error)
        }
    }

    /// Pflanzt einen Baum. Das Rad bietet nichts unter 30 Minuten an.
    func plant(minutes: Int) async {
        await start(seconds: Double(max(SessionLength.minimum, minutes)) * 60, test: false)
    }

    /// Der Testbaum: derselbe Ablauf - Erlaubnis, Schild, Meldung, Kurzbefehle -
    /// in zwanzig Sekunden. Kein Baum, keine Minuten: er zaehlt nirgends.
    func plantTest() async {
        await start(seconds: SessionLength.testSeconds, test: true)
    }

    /// Erlaubnis, Session, Ende anmelden, Kurzbefehl - und der Schild erst,
    /// wenn die App zurueck ist.
    ///
    /// Reihenfolge mit Absicht. Erst die Erlaubnis - ohne Sperre keine
    /// Session. Dann die Session festhalten, **bevor** irgendetwas gesperrt
    /// wird: wuerde die App dazwischen beendet, staende sonst ein Schild ohne
    /// Session, den niemand mehr wegnimmt. Dann der Kurzbefehl: er verlaesst
    /// die App, und die Kurzbefehle-App ist selbst eine App - laege der Schild
    /// schon, kaeme „Fokus an" nie zum Laufen. Der Schild folgt, sobald die
    /// App wieder vorne ist (`reconcile`), oder sofort, wenn Kurzbefehle gar
    /// nicht aufging.
    private func start(seconds: TimeInterval, test: Bool) async {
        guard active == nil else { return }
        guard await authorise() else { return }
        await Notifications.requestPermission()

        let now = Date()
        let session = ActiveSession(id: UUID().uuidString.lowercased(),
                                    start: now,
                                    end: now.addingTimeInterval(seconds),
                                    test: test)
        active = session
        Self.write(session, key: Self.activeKey)
        await scheduleEndNotification(session)
        errorMessage = nil
        watchEnd()
        let left = await ShortcutsBridge.focusOn(until: session.end)
        if !left { applyShield() }
    }

    /// Die Erlaubnis „Bildschirmzeit" - vor dem Pflanzen und vor dem
    /// Whitelist-Blatt: Apples App-Auswahl zeigt ohne sie keine einzige App,
    /// nur eine leere Liste ohne Erklaerung.
    func authorise() async -> Bool {
        defer { screenTimeNote = screenTime.note }
        do {
            try await screenTime.authorise()
            return true
        } catch {
            errorMessage = ScreenTimeGuard.explain(error)
            return false
        }
    }

    /// Bringt die Session auf den Stand der Uhr. Von ueberall aufrufbar,
    /// beliebig oft: beim Start, beim Aktivwerden, vom Timer. Vorbei: Baum
    /// melden. Laeuft noch, aber ohne Schild (die App war beim Kurzbefehl):
    /// Schild drauf.
    func reconcile() async {
        guard let session = active else { return }
        if session.isOver() {
            await finish(session)
        } else if !session.shielded {
            applyShield()
        }
    }

    /// Was die Kurzbefehle-App bei der Rueckkehr sagt - ein Fehler landet in
    /// der Leiste, sonst wuesste niemand, dass „Fokus an" fehlt.
    func handleCallback(_ url: URL) {
        guard let back = ShortcutsBridge.Return(url: url) else { return }
        if let note = back.note { errorMessage = note }
    }

    private func applyShield() {
        guard var session = active, !session.shielded, !session.isOver() else { return }
        do {
            try screenTime.shield(except: whitelist, until: session)
        } catch {
            // Der Schild liegt; nur das Ende ist bei DeviceActivity nicht
            // angemeldet. Dann nimmt ihn die App weg, sobald sie nach dem
            // Ende wieder laeuft - spaeter, aber sicher.
            print("Ende der Session nicht angemeldet: \(error.localizedDescription)")
        }
        session.shielded = true
        active = session
        Self.write(session, key: Self.activeKey)
    }

    private func finish(_ session: ActiveSession) async {
        endWatcher?.cancel()
        endWatcher = nil
        screenTime.lift()
        active = nil
        UserDefaults.standard.removeObject(forKey: Self.activeKey)
        if !session.test {
            // Erst lokal festhalten, dann melden: geht das Melden schief, ist
            // der Baum nicht weg, sondern wartet.
            unsynced.append(FocusSession(id: session.id, start: session.start, end: session.end,
                                         minutes: session.minutes,
                                         day: CalendarDate(date: session.start)))
            persistUnsynced()
            await syncPending()
        }
        await ShortcutsBridge.focusOff()
        await load()
    }

    /// Reicht nach, was der Dienst noch nicht hat. Nur mit Netz: ohne
    /// landete jeder Versuch noch einmal im Postausgang.
    private func syncPending() async {
        let known = Set(sessions.map(\.id))
        unsynced.removeAll { known.contains($0.id) }
        persistUnsynced()
        guard !unsynced.isEmpty, OfflineStatus.shared.staleSince[.habits] == nil else { return }
        for tree in unsynced {
            do {
                let planted = try await api.plant(
                    FocusSessionDraft(id: tree.id, start: tree.start, end: tree.end))
                unsynced.removeAll { $0.id == tree.id }
                if !sessions.contains(where: { $0.id == planted.id }) {
                    sessions.insert(planted, at: 0)
                }
            } catch APIError.queued {
                // Liegt im Postausgang; der Baum bleibt lokal stehen, bis der
                // Dienst ihn beim naechsten Laden kennt.
            } catch {
                report(error)
            }
        }
        persistUnsynced()
    }

    private func watchEnd() {
        endWatcher?.cancel()
        guard let session = active else { return }
        endWatcher = Task { [weak self] in
            let delay = session.end.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            // Sich selbst austragen, BEVOR es weitergeht: `finish` raeumt den
            // Waechter ab - waere das noch dieser Task, hiesse das, sich
            // selbst zu unterbrechen, und jede Netzanfrage danach scheiterte
            // mit „cancelled" (so kam die rote Zeile nach dem Testbaum).
            self?.endWatcher = nil
            await self?.reconcile()
        }
    }

    /// Die Meldung zum Ende der Session. Zeitkritisch, damit sie auch durch
    /// einen noch laufenden Fokus-Modus kommt. Feste Kennung: die Erweiterung
    /// ersetzt sie durch „Apps wieder frei", sobald sie den Schild weggenommen
    /// hat - so steht in der Mitteilung, ob das Ende wirklich angekommen ist.
    static let endNotificationID = "forest.end"

    private func scheduleEndNotification(_ session: ActiveSession) async {
        let content = UNMutableNotificationContent()
        content.title = session.test ? "Testbaum fertig" : "Baum gepflanzt"
        content.body = session.test ? "Zählt nicht." : "\(session.minutes) Minuten Fokus."
        content.sound = .default
        content.userInfo = ["kind": "forest"]
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, session.end.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: Self.endNotificationID,
                                            content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Speichern

    private func persistUnsynced() {
        Self.write(unsynced, key: Self.unsyncedKey)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? APIClient.decoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, key: String) {
        if let data = try? APIClient.encoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func report(_ error: Error) {
        if let apiError = error as? APIError, case .notAuthorised = apiError {
            isAccessProblem = true
        }
        errorMessage = error.localizedDescription
    }
}
