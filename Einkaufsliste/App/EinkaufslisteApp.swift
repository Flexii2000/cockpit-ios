import SwiftUI

/// Die Einkaufsliste als eigene App - fuer ein zweites Handy, das sonst
/// nichts von diesem Server sehen soll. Ein Token, eine Liste, kein Push,
/// kein Health, keine Kachel.
@main
struct EinkaufslisteApp: App {

    @State private var access = Access()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                // Muss laufen, bevor die erste Anfrage rausgeht - der Dienst
                // kennt die App nur an ihrem Cookie.
                .task { await access.applyCookies() }
        }
    }
}
