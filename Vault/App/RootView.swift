import SwiftUI

enum TabSelection: Hashable {
    case grades, finance

    static var initial: TabSelection {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "finance" { return .finance }
        #endif
        return .grades
    }
}

/// Welcher Tab offen ist - auch der Benachrichtigungs-Delegat stellt hier um.
@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selection: TabSelection = .initial
    private init() {}
    func show(_ tab: TabSelection) { selection = tab }
}

/// Eine Sperre vor der ganzen App.
///
/// Nicht je Tab wie frueher in der einen App: hier liegt hinter jedem Tab
/// etwas, das nicht offen herumstehen soll. Beim Verlassen zu, beim
/// Zurueckkommen gleich wieder fragen - wie eine Banking-App.
struct RootView: View {

    @Environment(Access.self) private var access
    @Environment(\.scenePhase) private var scenePhase

    let lock: BiometricLock

    private var router: Router { Router.shared }
    private var setup: SetupPresenter { SetupPresenter.shared }

    var body: some View {
        @Bindable var router = router
        @Bindable var setup = setup
        Group {
            if lock.isUnlocked {
                TabView(selection: $router.selection) {
                    Tab(Backend.grades.title, systemImage: Backend.grades.systemImage,
                        value: TabSelection.grades) {
                        GradesTab(lock: lock)
                    }
                    Tab(Backend.finance.title, systemImage: Backend.finance.systemImage,
                        value: TabSelection.finance) {
                        FinanceTab(lock: lock)
                    }
                }
            } else {
                LockScreen(title: "Vault ist gesperrt", failure: lock.lastFailure) {
                    await lock.unlock()
                }
            }
        }
        .task { await lock.unlock() }
        .onAppear {
            if !access.isGradesConfigured { setup.isPresented = true }
        }
        .sheet(isPresented: $setup.isPresented) {
            SetupView(sections: [.grades])
        }
        // Sichtschutz fuer den App-Umschalter: iOS macht die Vorschau in dem
        // Moment, in dem die App inaktiv wird.
        .overlay {
            if scenePhase != .active { privacyCover }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                lock.lock()
            } else {
                Task {
                    await lock.unlock()
                    await Outbox.shared.replay()
                }
            }
        }
    }

    private var privacyCover: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}
