import Foundation
import LocalAuthentication
import WebKit

/// Haelt die beiden Zugangstoken und macht daraus Cookies.
///
/// Die Backends kennen ausschliesslich Cookie-Auth (siehe docs/BACKENDS.md).
/// Im Browser stellt man die Cookies einmal pro Geraet ueber `/setup?token=…`
/// aus; die App spart sich das Ritual und setzt sie direkt. Sie muessen in
/// ZWEI Speicher, sonst funktioniert jeweils die eine Haelfte der App nicht:
///
/// * `WKWebsiteDataStore.default()` - fuer die WebView-Tabs
/// * `HTTPCookieStorage.shared`     - fuer die `URLSession` der nativen Tabs
@MainActor
@Observable
final class Access {

    /// Die Namen stehen in `Keychain` - das Widget braucht sie ebenfalls,
    /// und diese Klasse darf nicht mit in die Erweiterung.
    static let privateTokenKey = Keychain.privateTokenKey
    static let weightTokenKey = Keychain.weightTokenKey
    static let gradesTokenKey = Keychain.gradesTokenKey

    private static let migrationKey = "keychain.accessibility.afterFirstUnlock"

    private(set) var privateToken: String?
    private(set) var weightToken: String?

    /// Die Notenuebersicht hat einen eigenen Geraete-Token und dahinter eine
    /// Anmeldung mit Benutzer und Passwort. Der Token und der Benutzername
    /// liegen offen im Keychain, das Passwort hinter Face ID.
    private(set) var gradesToken: String?
    private(set) var gradesUser: String?
    private(set) var hasGradesPassword = false

    /// Ob der Noten-Tab etwas versuchen kann. Absichtlich nicht Teil von
    /// `isConfigured`: die drei uebrigen Tabs laufen ohne die Noten weiter,
    /// und wer sie nicht eingerichtet hat, soll nicht bei jedem Start auf dem
    /// Zugang-Bildschirm landen.
    var isGradesConfigured: Bool {
        gradesToken != nil && gradesUser != nil && hasGradesPassword
    }

    /// Ohne beide Token bleibt die App leer - dann zeigt `RootView` die
    /// Einrichtung, statt drei Tabs mit Fehlermeldungen anzubieten.
    var isConfigured: Bool { privateToken != nil && weightToken != nil }

    init() {
        privateToken = Keychain.read(Self.privateTokenKey)
        weightToken = Keychain.read(Self.weightTokenKey)
        gradesToken = Keychain.read(Self.gradesTokenKey)
        gradesUser = Keychain.read(Keychain.gradesUserKey)
        hasGradesPassword = Keychain.hasProtected(Keychain.gradesPasswordKey)
        #if DEBUG
        // Muss hier passieren und nicht erst in einer `.task`: `RootView`
        // entscheidet beim Erscheinen, ob es zum Zugang-Bildschirm springt -
        // und das ist frueher.
        seedFromEnvironment()
        #endif
        migrateAccessibility()
    }

    /// Schreibt die beiden Token einmal neu.
    ///
    /// `kSecAttrAccessible` gilt je Eintrag und wird beim Aendern der Konstante
    /// **nicht** nachgezogen: ein Eintrag, der mit `WhenUnlocked` angelegt
    /// wurde, bleibt so, bis ihn jemand ersetzt. Ohne diesen Durchlauf
    /// scheitert das Widget bei gesperrtem Geraet weiter - obwohl die
    /// Konstante in `Keychain` laengst geaendert ist.
    private func migrateAccessibility() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        if let privateToken { Keychain.save(privateToken, for: Self.privateTokenKey) }
        if let weightToken { Keychain.save(weightToken, for: Self.weightTokenKey) }
        defaults.set(true, forKey: Self.migrationKey)
    }

    func store(privateToken: String, weightToken: String) async {
        let p = privateToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = weightToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(p, for: Self.privateTokenKey)
        Keychain.save(w, for: Self.weightTokenKey)
        self.privateToken = p
        self.weightToken = w
        await applyCookies()
    }

#if DEBUG
    /// Nimmt die Token aus der Prozessumgebung, falls welche da sind.
    ///
    /// Nur fuer den Simulator (siehe `tools/run-simulator.sh`): sonst muesste
    /// man sie vor jedem Blick auf die Oberflaeche von Hand eintippen, und
    /// ohne Token zeigen die Tabs nur Fehlermeldungen. Bewusst hinter
    /// `#if DEBUG` - ein Token, das ueber eine Umgebungsvariable in die App
    /// kommt, hat in einem Build fuer ein echtes Geraet nichts zu suchen.
    func seedFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["COCKPIT_FH_PRIVATE_TOKEN"], !value.isEmpty {
            Keychain.save(value, for: Self.privateTokenKey)
            privateToken = value
        }
        if let value = environment["COCKPIT_WEIGHT_TOKEN"], !value.isEmpty {
            Keychain.save(value, for: Self.weightTokenKey)
            weightToken = value
        }
        if let value = environment["COCKPIT_GRADES_TOKEN"], !value.isEmpty {
            Keychain.save(value, for: Self.gradesTokenKey)
            gradesToken = value
        }
        if let value = environment["COCKPIT_GRADES_USER"], !value.isEmpty {
            Keychain.save(value, for: Keychain.gradesUserKey)
            gradesUser = value
        }
        // Bewusst OHNE Face-ID-Schutz: im Simulator ist kein Gesicht
        // hinterlegt, ein geschuetzter Eintrag waere dort nicht mehr zu lesen
        // und der Tab nicht aufzunehmen. Auf dem Geraet passiert das nie -
        // dort setzt niemand Umgebungsvariablen.
        if let value = environment["COCKPIT_GRADES_PASSWORD"], !value.isEmpty {
            Keychain.save(value, for: Keychain.gradesPasswordKey)
            hasGradesPassword = true
        }
    }
#endif

    /// Legt Zugang zur Notenuebersicht ab.
    ///
    /// - Returns: `false`, wenn das Passwort nicht hinter Face ID gelegt
    ///   werden konnte - dann hat das Geraet keinen Code, und ohne Code gibt
    ///   es nichts, womit sich jemand ausweisen koennte.
    @discardableResult
    func storeGrades(token: String, user: String, password: String) async -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        // Das Passwort NICHT beschneiden: ein fuehrendes oder abschliessendes
        // Leerzeichen darin ist erlaubt, und stillschweigend zu kuerzen hiesse
        // eine Anmeldung, die im Browser geht und hier nicht.
        guard Keychain.saveProtected(password, for: Keychain.gradesPasswordKey) else {
            return false
        }
        Keychain.save(t, for: Self.gradesTokenKey)
        Keychain.save(u, for: Keychain.gradesUserKey)
        gradesToken = t
        gradesUser = u
        hasGradesPassword = true
        await applyCookies()
        return true
    }

    /// Holt das Passwort heraus.
    ///
    /// Der Kontext muss seine Pruefung hinter sich haben (siehe
    /// `Keychain.readProtected`) - sonst zeigt die Keychain die Abfrage
    /// selbst und friert dabei die Oberflaeche ein.
    func gradesPassword(context: LAContext?) -> String? {
        Keychain.readProtected(Keychain.gradesPasswordKey, context: context)
    }

    func reset() {
        Keychain.delete(Self.privateTokenKey)
        Keychain.delete(Self.weightTokenKey)
        privateToken = nil
        weightToken = nil
    }

    func resetGrades() {
        Keychain.delete(Self.gradesTokenKey)
        Keychain.delete(Keychain.gradesUserKey)
        Keychain.delete(Keychain.gradesPasswordKey)
        gradesToken = nil
        gradesUser = nil
        hasGradesPassword = false
    }

    /// Muss laufen, BEVOR eine WebView laedt oder eine API-Anfrage rausgeht.
    func applyCookies() async {
        var cookies: [HTTPCookie] = []
        // Domain mit fuehrendem Punkt: das Privat-Token gilt fuer alle
        // Subdomains von fherrmann.com, genau wie das Cookie, das
        // fherrmann.com/setup ausstellt.
        if let privateToken, let c = Self.cookie(name: Self.privateTokenKey,
                                                 value: privateToken,
                                                 domain: ".fherrmann.com") {
            cookies.append(c)
        }
        // Das Weight-Token gehoert genau einer Domain - kein Grund, es
        // breiter zu streuen als noetig.
        if let weightToken, let c = Self.cookie(name: Self.weightTokenKey,
                                                value: weightToken,
                                                domain: "weight.fherrmann.com") {
            cookies.append(c)
        }
        // Der Noten-Token gilt nur fuer den einen Pfad - so stellt ihn auch
        // `/grades/setup` aus. Breiter gesetzt liefe er bei jeder Anfrage an
        // fherrmann.com mit, ohne dass ihn dort jemand braucht.
        //
        // Rechner und Pfad kommen aus `Backend.grades.url` statt fest im Code
        // zu stehen: im Debug-Build kann die Adresse auf einen lokal
        // laufenden Dienst zeigen, und ein Cookie fuer fherrmann.com waere
        // dorthin nie mitgegangen.
        let gradesURL = Backend.grades.url
        if let gradesToken, let host = gradesURL.host(),
           let c = Self.cookie(name: Self.gradesTokenKey,
                               value: gradesToken,
                               domain: host,
                               path: gradesURL.path(),
                               secure: gradesURL.scheme == "https") {
            cookies.append(c)
        }
        #if DEBUG
        // Ist der Habits-Dienst auf eine andere Adresse umgeleitet
        // (COCKPIT_URL_HABITS, lokal gestarteter Dienst), gilt das Cookie fuer
        // .fherrmann.com dort nicht. Dann dasselbe Token noch einmal fuer
        // diesen Rechner - ohne das antwortet der lokale Dienst nur mit 403.
        let habitsURL = Backend.habits.url
        if let privateToken, let host = habitsURL.host(), !host.hasSuffix("fherrmann.com"),
           let c = Self.cookie(name: Self.privateTokenKey, value: privateToken,
                               domain: host, path: habitsURL.path(),
                               secure: habitsURL.scheme == "https") {
            cookies.append(c)
        }
        #endif
        // Erst alle in den gemeinsamen Speicher - der geht ohne Warten. Wer
        // beides verschraenkt, laesst zwischen dem ersten und dem letzten
        // Cookie ein Zeitfenster offen, in dem eine schon laufende Anfrage
        // ohne ihres losgeht. Genau das ist beim Noten-Tab passiert: er fragt
        // beim Erscheinen, und das war frueher als sein Cookie.
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            await store.setCookie(cookie)
        }
    }

    private static func cookie(name: String, value: String, domain: String,
                               path: String = "/", secure: Bool = true) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            // Ein Jahr. Die Token selbst leben laenger; laeuft das Cookie doch
            // einmal ab, setzt der naechste App-Start es neu aus dem Keychain.
            .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365),
        ]
        // Nur setzen, wenn es zutrifft: ein sicheres Cookie geht ueber http
        // gar nicht erst mit, und beim lokalen Dienst gibt es kein TLS.
        if secure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}
