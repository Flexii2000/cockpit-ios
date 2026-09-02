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

    private init() {}

    /// Zeigt einen Tab - z. B. nach einem Tipp auf eine Benachrichtigung.
    func show(_ tab: TabSelection) {
        selection = tab
    }
}
