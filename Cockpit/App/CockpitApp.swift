import SwiftUI

@main
struct CockpitApp: App {

    @State private var access = Access()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                // Muss laufen, bevor die erste WebView laedt - sonst schickt
                // nginx den Kalorienzaehler-Tab auf die Startseite um.
                .task { await access.applyCookies() }
        }
    }
}
