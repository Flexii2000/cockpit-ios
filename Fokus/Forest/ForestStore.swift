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
    var shortcutsEnabled: Bool {
        didSet { ShortcutsBridge.isEnabled = shortcutsEnabled }
    }

    /// So weit reicht der Wald zurueck. Aeltere Baeume stehen weiter beim
    /// Dienst, nur nicht auf dem Bildschirm.
    static let historyDays = 90

    private static let activeKey = "forest.active"
    private static let unsyncedKey = "forest.unsynced"
    private var endWatcher: Task<Void, Never>?

    init() {
        whitelist = Whitelist.load()
        shortcutsEnabled = ShortcutsBridge.isEnabled
        active = Self.read(ActiveSession.self, key: Self.activeKey)
        unsynced = Self.read([FocusSession].self, key: Self.unsyncedKey) ?? []
        #if DEBUG
        // Nur fuers Bild: eine Session, die vor zehn Minuten begann. Ohne
        // Schild - im Simulator gibt es keinen - und ohne Baum am Ende.
        if active == nil,
           let raw = ProcessInfo.processInfo.environment["COCKPIT_FOREST_RUNNING"],
           let minutes = Int(raw) {
            active = ActiveSession(id: Self.demoID,
                                   start: Date().addingTimeInterval(-600),
                                   end: Date().addingTimeInterval(Double(minutes) * 60))
        }
        #endif
        watchEnd()
    }

    private static let demoID = "demo"

    /// Der Wald: Tage mit ihren Baeumen, neueste zuerst. Lokal Fertiges steht
    /// mit drin, solange der Dienst es noch nicht hat.
    var days: [ForestDay] {
        let known = Set(sessions.map(\.id))
        return ForestDay.group(sessions + unsynced.filter { !known.contains($0.id) })
    }

    var todayMinutes: Int {
        days.first { $0.day == .today() }?.minutes ?? 0
    }

    /// Das Tagesziel aus dem Habit „Fokus-Zeit" - ohne Habit kein Ziel.
    var dailyGoal: Int? {
        focusHabit?.focusMinutesGoal ?? focusHabit?.progress?.goal
    }

    func load() async {
        isLoading = sessions.isEmpty
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

    /// Pflanzt einen Baum: Erlaubnis, Schild, Ende anmelden, Kurzbefehl.
    ///
    /// Reihenfolge mit Absicht. Erst die Erlaubnis - ohne Sperre keine
    /// Session. Dann die Session festhalten, **bevor** der Schild liegt: wuerde
    /// die App zwischen beidem beendet, staende sonst ein Schild ohne Session,
    /// den niemand mehr wegnimmt. Der Kurzbefehl zuletzt, weil er die App
    /// verlaesst.
    func plant(minutes: Int) async {
        guard active == nil else { return }
        // Das Rad bietet nichts unter 30 Minuten an; die eine Minute des
        // Testbaums kommt aus dem Menue und ist erlaubt.
        let minutes = max(SessionLength.test, minutes)
        guard await authorise() else { return }
        await Notifications.requestPermission()

        let now = Date()
        let session = ActiveSession(id: UUID().uuidString.lowercased(),
                                    start: now,
                                    end: now.addingTimeInterval(Double(minutes) * 60))
        active = session
        Self.write(session, key: Self.activeKey)
        do {
            try screenTime.shield(except: whitelist, until: session)
        } catch {
            // Der Schild liegt; nur das Ende ist bei DeviceActivity nicht
            // angemeldet. Dann nimmt ihn die App weg, sobald sie nach dem
            // Ende wieder laeuft - spaeter, aber sicher.
            print("Ende der Session nicht angemeldet: \(error.localizedDescription)")
        }
        await scheduleEndNotification(session)
        errorMessage = nil
        watchEnd()
        ShortcutsBridge.focusOn(until: session.end)
    }

    /// Die Erlaubnis „Bildschirmzeit" - vor dem Pflanzen und vor dem
    /// Whitelist-Blatt: Apples App-Auswahl zeigt ohne sie keine einzige App,
    /// nur eine leere Liste ohne Erklaerung.
    func authorise() async -> Bool {
        do {
            try await screenTime.authorise()
            return true
        } catch {
            errorMessage = ScreenTimeGuard.explain(error)
            return false
        }
    }

    /// Ist die Session vorbei, wird sie abgeschlossen. Von ueberall
    /// aufrufbar, beliebig oft: beim Start, beim Aktivwerden, vom Timer.
    func reconcile() async {
        guard let session = active, session.isOver() else { return }
        await finish(session)
    }

    private func finish(_ session: ActiveSession) async {
        endWatcher?.cancel()
        endWatcher = nil
        screenTime.lift()
        active = nil
        UserDefaults.standard.removeObject(forKey: Self.activeKey)
        #if DEBUG
        if session.id == Self.demoID { return }
        #endif
        // Erst lokal festhalten, dann melden: geht das Melden schief, ist der
        // Baum nicht weg, sondern wartet.
        unsynced.append(FocusSession(id: session.id, start: session.start, end: session.end,
                                     minutes: session.minutes,
                                     day: CalendarDate(date: session.start)))
        persistUnsynced()
        await syncPending()
        ShortcutsBridge.focusOff()
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
            await self?.reconcile()
        }
    }

    /// „Baum gepflanzt" zum Ende der Session. Zeitkritisch, damit sie auch
    /// durch einen noch laufenden Fokus-Modus kommt.
    private func scheduleEndNotification(_ session: ActiveSession) async {
        let content = UNMutableNotificationContent()
        content.title = "Baum gepflanzt"
        content.body = session.minutes == 1 ? "1 Minute Fokus." : "\(session.minutes) Minuten Fokus."
        content.sound = .default
        content.userInfo = ["kind": "forest"]
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, session.end.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: "forest.\(session.id)",
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
