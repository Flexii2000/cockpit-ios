import SwiftUI

/// Was in der Leiste unten steht: Padel zuerst, dort macht die App auf.
enum TabSelection: Hashable {
    case padel, gym

    /// Womit die App aufmacht. Im Debug-Build ueber `COCKPIT_TAB` vorgebbar.
    static var initial: TabSelection {
        #if DEBUG
        return ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "gym" ? .gym : .padel
        #else
        return .padel
        #endif
    }
}

/// Welcher Tab offen ist - erreichbar auch von ausserhalb der Oberflaeche.
@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selection: TabSelection = .initial

    private init() {}
}

struct RootView: View {

    @Environment(Access.self) private var access
    @Environment(\.scenePhase) private var scenePhase

    private var router: Router { Router.shared }
    private var setup: SetupPresenter { SetupPresenter.shared }

    var body: some View {
        @Bindable var router = router
        @Bindable var setup = setup
        TabView(selection: $router.selection) {
            Tab(Backend.padel.title, systemImage: Backend.padel.systemImage, value: TabSelection.padel) {
                PadelTab()
            }
            Tab("Gym", systemImage: "dumbbell", value: TabSelection.gym) {
                GymTab()
            }
        }
        .onAppear {
            // Ohne Token zeigen die Tabs nur Anmeldeseiten - dann gleich das Blatt dafuer.
            if access.privateToken == nil || access.weightToken == nil { setup.isPresented = true }
        }
        .sheet(isPresented: $setup.isPresented) {
            SetupView(sections: [.privateToken, .weightToken])
        }
        .onChange(of: scenePhase) { _, phase in
            // Zurueck im Vordergrund heisst oft: zurueck im Netz. Was wartet, darf jetzt raus.
            PendingSync.foreground(phase == .active)
            if phase == .active {
                SportWatchLink.shared.sendContext()
                Task { await PadelReportOutbox.shared.deliver(cookie: nil) }
            }
        }
    }
}
