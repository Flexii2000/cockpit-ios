import SwiftUI

/// Ein Tab, dessen Code nicht in diesem Repo liegt.
///
/// Er kommt aus dem Ordner `Private/` (nicht eingecheckt, siehe CLAUDE.md), den
/// project.yml nur mit uebersetzt, wenn es ihn gibt. Ohne ihn baut Fokus wie
/// immer und zeigt den Tab nicht. Der oeffentliche Code nennt den Typ nie beim
/// Namen: der Anbieter meldet sich zur Laufzeit unter dem Objective-C-Namen
/// `FokusPrivateTab` (`@objc(FokusPrivateTab)`, eine `NSObject`-Unterklasse).
@MainActor
protocol PrivateTabProvider: AnyObject {
    init()
    var title: String { get }
    var systemImage: String { get }
    /// Der Inhalt des Tabs.
    func makeView() -> AnyView
    /// Ob ein Link aus einer Meldung (`link` der Nutzlast) zu diesem Tab gehoert.
    /// Dann oeffnet die App den Tab statt Safari.
    func handles(_ link: URL) -> Bool
    /// Aus `application(_:didFinishLaunchingWithOptions:)` - auch wenn iOS die App
    /// im Hintergrund startet und keine Oberflaeche aufbaut.
    func didFinishLaunching()
}

@MainActor
enum PrivateTab {
    /// Der Anbieter, falls `Private/` mit uebersetzt wurde - sonst `nil`.
    static let provider: (any PrivateTabProvider)? = {
        guard let type = NSClassFromString("FokusPrivateTab") as? any PrivateTabProvider.Type else {
            return nil
        }
        return type.init()
    }()
}
