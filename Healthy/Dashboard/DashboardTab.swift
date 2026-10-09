import SwiftUI

/// Das Dashboard - ganz links, und dort macht die App auf (Felix, 09.10.).
///
/// Ein Blick auf den Tag: Recovery, Energie, Gewicht, was vom kcal-Ziel
/// uebrig ist, Schritte, Logbook. Jede Karte fuehrt dorthin, wo das Einzelne
/// steht: Recovery und Logbook auf ihre Seite, Energie und kcal in den
/// Essen-Tab mit heute, Gewicht in seinen Tab.
///
/// Nicht zu verwechseln mit `/api/dashboard` des Weight Trackers - das ist die
/// Auswahl der Kacheln im Gewicht-Tab.
struct DashboardTab: View {

    @State private var store = DashboardStore()

    private var router: Router { Router.shared }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.dashboardPath) {
            ScrollView {
                VStack(spacing: 12) {
                    if let message = store.accessMessage {
                        ErrorBanner(message: message, isAccessProblem: true)
                    }
                    if !store.hasLoaded {
                        LoadingPlaceholder()
                    }
                    cards
                }
                .padding(16)
                // Platz fuer die schwebende Tab-Leiste, wie im Gewicht-Tab.
                .padding(.bottom, 60)
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backends: [.food, .weight]) }
            .navigationTitle("Dashboard")
            .navigationDestination(for: DashboardPage.self) { page in
                switch page {
                case .recovery: RecoveryView()
                case .logbook:  LogbookView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Zugang …") { SetupPresenter.shared.isPresented = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await HealthSync.shared.syncAll(force: true)
                await store.load()
            }
            .task {
                await store.load()
                #if DEBUG
                // Erfundene Werte - die echten aus Health gehoeren nicht dazu.
                if DashboardDemo.isOn { return }
                #endif
                // Erlaubnis im Zusammenhang erfragen: hier ist zu sehen, wofuer
                // sie gebraucht wird. Fehlt keine, wird abgeglichen, wenn es
                // faellig ist.
                await HealthSync.shared.connect()
            }
            // Hat der Abgleich etwas hochgeladen, steht beim Dienst ein neuer
            // Stand - die Nacht von heute frueh etwa.
            .onChange(of: HealthSync.shared.uploads) {
                Task { await store.load() }
            }
            .onChange(of: OfflineStatus.shared.pending) { before, after in
                if before > 0, after == 0 { Task { await store.load() } }
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        if let recovery = store.recovery {
            NavigationLink(value: DashboardPage.recovery) {
                RecoveryCard(day: recovery)
            }
            .buttonStyle(.plain)
            // Anker fuer die UI-Tests - am Knopf, nicht an der Karte darin:
            // ein Container ist nie „hittable".
            .accessibilityIdentifier("recoveryCard")
        }
        // Ohne Defizit heute und ohne Wert in der Woche fehlt die Karte
        // (Vertrag §5) - etwa ohne Kalorienzaehler: dann ist die Aufnahme
        // unbekannt, und der Verbrauch allein ist keine Bilanz.
        if let energy = EnergyCardModel(summary: store.energy, week: store.energyWeek ?? [],
                                        today: .today()) {
            Button { router.showFoodToday() } label: {
                EnergyCard(model: energy)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("energyCard")
        }
        if store.weight != nil || store.food != nil {
            HStack(alignment: .top, spacing: 12) {
                if let weight = store.weight {
                    Button { router.show(.weight) } label: { WeightHalfCard(summary: weight) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("weightCard")
                }
                if let food = store.food {
                    Button { router.showFoodToday() } label: { FoodHalfCard(day: food, steps: store.steps) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("foodCard")
                }
            }
            // Beide Haelften gleich hoch, auch wenn eine eine Zeile mehr hat.
            .fixedSize(horizontal: false, vertical: true)
        }
        if let logbook = store.logbook {
            NavigationLink(value: DashboardPage.logbook) {
                LogbookCard(overview: logbook, insights: store.insights, queued: store.queuedLogbookDays)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("logbookCard")
        }
    }
}
