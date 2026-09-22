import FamilyControls
import Foundation
import ManagedSettings

/// Was App und Erweiterung `FokusMonitor` gemeinsam wissen muessen - in der
/// App-Gruppe, denn die Erweiterung sieht die UserDefaults der App nicht.
///
/// Warum die Erweiterung das braucht: nach einem Neustart des Handys legt
/// iOS den Schild nicht von selbst wieder auf. Das angemeldete Intervall
/// laeuft aber weiter und meldet sich bei der Erweiterung (`intervalDidStart`)
/// - die liest hier die laufende Session und die erlaubten Apps und legt den
/// Schild erneut. Ohne das war ein Neustart der Weg an der Sperre vorbei
/// (Felix, 2026-09-21).
enum FocusHandoff {

    /// Die App-Gruppe von Fokus und FokusMonitor (project.yml).
    static let group = "group.com.fherrmann.fokus"

    /// Der Name des Intervalls bei DeviceActivity.
    static let activityName = "fokus.session"

    /// Die Kennung der Meldung zum Ende der Session: die App plant sie vor,
    /// die Erweiterung ersetzt sie durch „Apps wieder frei".
    static let endNotificationID = "forest.end"

    private static let sessionKey = "forest.active"
    private static let todayMinutesKey = "forest.todayMinutes"
    private static let todayGoalKey = "forest.todayGoal"
    private static let todayDateKey = "forest.todayDate"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: group) ?? .standard
    }

    // MARK: - Die laufende Session

    static func loadSession() -> ActiveSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? decoder().decode(ActiveSession.self, from: data)
    }

    static func save(_ session: ActiveSession) {
        if let data = try? encoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    static func clearSession() {
        defaults.removeObject(forKey: sessionKey)
    }

    // MARK: - Der Stand von heute (fuer die Kachel)

    /// Die App legt nach jedem Laden ab, wie viele Fokus-Minuten heute
    /// zusammenkamen und was das Ziel ist - die Kachel hat kein Netz und
    /// zeigt das, sobald keine Session laeuft. Mit dem Datum: ein alter Stand
    /// von gestern gilt nicht mehr.
    static func saveToday(minutes: Int, goal: Int?) {
        defaults.set(minutes, forKey: todayMinutesKey)
        defaults.set(goal ?? 0, forKey: todayGoalKey)
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: todayDateKey)
    }

    static func loadToday() -> (minutes: Int, goal: Int?) {
        guard let raw = defaults.string(forKey: todayDateKey),
              let stamp = ISO8601DateFormatter().date(from: raw),
              Calendar.current.isDateInToday(stamp) else { return (0, nil) }
        let goal = defaults.integer(forKey: todayGoalKey)
        return (defaults.integer(forKey: todayMinutesKey), goal > 0 ? goal : nil)
    }

    // MARK: - Der Schild

    /// Alle Kategorien sperren bis auf die erlaubten Apps - dieselbe Regel in
    /// App und Erweiterung, deshalb hier.
    static func applyShield(except allowed: FamilyActivitySelection, to store: ManagedSettingsStore) {
        store.shield.applicationCategories = .all(except: allowed.applicationTokens)
        store.shield.webDomainCategories = .all(except: allowed.webDomainTokens)
        store.shield.applications = nil
        store.shield.webDomains = nil
    }

    // MARK: - Kodierung

    /// ISO-Zeitpunkte, damit die Datei lesbar bleibt und beide Seiten
    /// dasselbe verstehen - `JSONEncoder` schriebe sonst Sekunden seit 2001.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Eine laufende Session: der Baum, der gerade waechst.
///
/// Liegt in der App-Gruppe, nicht nur im Speicher - die App darf
/// zwischendurch beendet werden, und die Erweiterung muss sie nach einem
/// Neustart finden. Abbrechen gibt es nicht: die Session endet, wenn `end`
/// erreicht ist.
struct ActiveSession: Codable, Sendable, Equatable {
    let id: String
    let start: Date
    let end: Date
    /// Ob der Schild schon liegt. Er kommt erst, wenn der Kurzbefehl durch
    /// ist: die Kurzbefehle-App ist selbst eine App und laege sonst mit
    /// darunter - „Fokus an" koennte nie laufen.
    var shielded = false
    /// Der Testbaum: gleicher Ablauf, aber am Ende kein Baum und keine
    /// Minuten - er zaehlt nirgends.
    let test: Bool

    init(id: String, start: Date, end: Date, shielded: Bool = false, test: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.shielded = shielded
        self.test = test
    }

    /// `shielded` und `test` duerfen fehlen: eine Session aus einem Stand,
    /// der die Felder noch nicht kannte, gilt als geschuetzt und echt.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        shielded = try container.decodeIfPresent(Bool.self, forKey: .shielded) ?? true
        test = try container.decodeIfPresent(Bool.self, forKey: .test) ?? false
    }

    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }

    func isOver(at now: Date = Date()) -> Bool { now >= end }

    /// 0 beim Pflanzen, 1 am Ende - so weit ist der Baum gewachsen.
    func growth(at now: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }
}
