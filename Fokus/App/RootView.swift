import SwiftUI

enum TabSelection: Hashable {
    case todo, forest
    #if DEBUG
    case widget

    static var showsWidgetPreview: Bool {
        ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "widget"
    }
    #endif

    static var initial: TabSelection {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "widget": return .widget
        case "forest": return .forest
        default:       break
        }
        #endif
        // Die Habits sind nach coHabit umgezogen - vorn steht jetzt To-Do.
        return .todo
    }
}

@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selection: TabSelection = .initial
    private init() {}
    func show(_ tab: TabSelection) { selection = tab }
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
            Tab(Backend.todo.title, systemImage: Backend.todo.systemImage, value: TabSelection.todo) {
                TodoTab()
            }
            Tab("Wald", systemImage: "tree", value: TabSelection.forest) {
                ForestTab()
            }
            #if DEBUG
            if TabSelection.showsWidgetPreview {
                Tab("Kachel", systemImage: "square.grid.2x2", value: TabSelection.widget) {
                    WidgetPreviewTab()
                }
            }
            #endif
        }
        .onAppear {
            if access.privateToken == nil { setup.isPresented = true }
        }
        .sheet(isPresented: $setup.isPresented) {
            SetupView(sections: [.privateToken])
        }
        // Ein Tipp auf die Fokus-Kachel (`.widgetURL`) - oder die Rueckkehr
        // aus der Kurzbefehle-App (`cockpit-fokus://forest`, siehe
        // ShortcutsBridge).
        .onOpenURL { url in
            if url.host() == "forest" { router.show(.forest) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await Outbox.shared.replay() } }
        }
    }
}
