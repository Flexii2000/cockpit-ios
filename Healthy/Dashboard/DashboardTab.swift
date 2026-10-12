import SwiftUI

/// Das Dashboard - ganz links, und dort macht die App auf (Felix, 09.10.).
///
/// Ein Blick auf den Tag: Recovery, Energie, Gewicht, was vom kcal-Ziel
/// uebrig ist, Schritte - und darunter das Logbook samt Effekten, direkt zum
/// Eintragen (seit 12.10.). Die Karten oben fuehren dorthin, wo das Einzelne
/// steht: Recovery auf ihre Seite, Energie und kcal in den Essen-Tab mit heute,
/// Gewicht in seinen Tab.
///
/// Nicht zu verwechseln mit `/api/dashboard` des Weight Trackers - das ist die
/// Auswahl der Kacheln im Gewicht-Tab.
struct DashboardTab: View {

    @State private var store = DashboardStore()
    @State private var logbook = LogbookStore()
    @Environment(\.scenePhase) private var scenePhase

    private var router: Router { Router.shared }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.dashboardPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if let message = store.accessMessage {
                            ErrorBanner(message: message, isAccessProblem: true)
                        }
                        if !store.hasLoaded {
                            LoadingPlaceholder()
                        }
                        cards
                        LogbookSection(store: logbook)
                            .id(DashboardAnchor.logbook)
                        LogbookEffectsSection(store: logbook)
                            .id(DashboardAnchor.effects)
                    }
                    .padding(16)
                    // Platz fuer die schwebende Tab-Leiste, wie im Gewicht-Tab.
                    .padding(.bottom, 60)
                }
                // Der Tipp auf „gestern offen“: hierher, auf gestern.
                .onChange(of: router.logbookRequests) {
                    logbook.followToday(reminder: true)
                    withAnimation { proxy.scrollTo(DashboardAnchor.logbook, anchor: .top) }
                }
                .task {
                    guard let anchor = DashboardAnchor.initial else { return }
                    await logbook.load()
                    // Erst wenn die Karten stehen, gibt es die Stelle.
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backends: [.food, .weight]) }
            .navigationTitle("Dashboard")
            .navigationDestination(for: DashboardPage.self) { page in
                switch page {
                case .recovery: RecoveryView()
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
                async let cards: Void = store.load()
                async let entries: Void = logbook.load(forceInsights: true)
                _ = await (cards, entries)
            }
            .task {
                async let cards: Void = store.load()
                async let entries: Void = logbook.load()
                _ = await (cards, entries)
                #if DEBUG
                // Erfundene Werte - die echten aus Health gehoeren nicht dazu.
                if DashboardDemo.isOn { return }
                #endif
                // Erlaubnis im Zusammenhang erfragen: hier ist zu sehen, wofuer
                // sie gebraucht wird. Fehlt keine, wird abgeglichen, wenn es
                // faellig ist.
                await HealthSync.shared.connect()
            }
            // Welcher Tag im Logbook: neu, wenn das Dashboard erscheint, die App
            // zurueckkommt und um Mitternacht.
            .onAppear { logbook.followToday() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { logbook.followToday() }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Self.secondsUntilTomorrow()))
                    if Task.isCancelled { return }
                    logbook.followToday()
                }
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

    /// Bis kurz nach Mitternacht - ueber den Kalender, wegen der Zeitumstellung.
    private static func secondsUntilTomorrow(now: Date = Date()) -> Double {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: now).addingTimeInterval(36 * 3600)
        let midnight = calendar.startOfDay(for: tomorrow)
        return max(midnight.timeIntervalSince(now) + 1, 1)
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
    }
}
