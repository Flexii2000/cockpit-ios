import SwiftUI

/// Welcher Tab offen ist - an einer Stelle, an die auch der AppDelegate kommt.
///
/// Gebraucht wird das fuer die Benachrichtigungen: wer auf „Neue Note 1,7"
/// tippt, will die Noten sehen und nicht den Tab, der zuletzt offen war. Der
/// AppDelegate steht ausserhalb der SwiftUI-Umgebung und kaeme an einen
/// `@State` in `RootView` nicht heran.
@MainActor
@Observable
final class Router {

    /// Eine Instanz fuer die ganze App. Kein Umweg ueber die Umgebung: es gibt
    /// genau ein Fenster, und der AppDelegate braucht denselben Zeiger.
    static let shared = Router()

    var selection: TabSelection = .initial

    /// Ob das Zugang-Blatt offen ist.
    ///
    /// Seit dem sechsten Tab ist Zugang kein Tab mehr: iOS zeigt hoechstens
    /// fuenf in der Leiste und schiebt den Rest unter „Mehr". Zugang wird
    /// selten gebraucht - ein Zahnrad in der Leiste oben reicht.
    var showsSetup = false

    private init() {
        #if DEBUG
        // COCKPIT_TAB=setup gibt es weiter, nur oeffnet es jetzt das Blatt.
        if ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "setup" {
            showsSetup = true
        }
        #endif
    }

    /// Zeigt einen Tab - z. B. nach einem Tipp auf eine Benachrichtigung.
    func show(_ tab: TabSelection) {
        selection = tab
    }
}
