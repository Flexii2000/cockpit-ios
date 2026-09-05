import SwiftUI

/// Kein Tab-Balken: die App hat genau eine Seite. Ohne Token geht gleich das
/// Zugang-Blatt auf - mit nur dem einen Abschnitt, den diese App kennt.
struct RootView: View {

    @Environment(Access.self) private var access
    @Environment(\.scenePhase) private var scenePhase

    private var setup: SetupPresenter { SetupPresenter.shared }

    var body: some View {
        @Bindable var setup = setup
        ShoppingTab()
            .onAppear {
                if access.shoppingToken == nil { setup.isPresented = true }
            }
            .sheet(isPresented: $setup.isPresented) {
                SetupView(sections: [.shoppingToken])
            }
            .onChange(of: scenePhase) { _, phase in
                // Zurueck im Vordergrund heisst oft: zurueck im Netz - also
                // raus aus dem Laden. Was im Postausgang wartet, darf jetzt los.
                if phase == .active { Task { await Outbox.shared.replay() } }
            }
    }
}
