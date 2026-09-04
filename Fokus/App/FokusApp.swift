import SwiftUI

/// Habits - und spaeter To-Do und Roadmap.
@main
struct FokusApp: App {

    @State private var access = Access()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(access)
                .task { await access.applyCookies() }
        }
    }
}
