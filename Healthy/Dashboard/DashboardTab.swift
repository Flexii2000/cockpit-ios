import SwiftUI

/// Das Dashboard - ganz links, und dort macht die App auf (Felix, 09.10.).
///
/// Ein Blick auf den Tag: Recovery, Strain (seit 10.11.), Energie, Gewicht, was
/// vom kcal-Ziel uebrig ist, Schritte - und darunter das Logbook samt Effekten,
/// direkt zum Eintragen (seit 12.10.). Die Karten oben fuehren dorthin, wo das
/// Einzelne steht: Recovery auf ihre Seite, Strain in sein Fenster, Energie und
/// kcal in den Essen-Tab mit heute, Gewicht in seinen Tab, Serien zu den Freunden.
///
/// Seit 10.11. dazu (Vertrag §5): ganz oben das Morgen-Briefing, die Kacheln
/// „Serien“ und „Eichung“, ganz unten der Wochenrueckblick - und in der Leiste
/// der Chat mit der Claude-Instanz auf dem Server, wo er freigeschaltet ist.
///
/// Nicht zu verwechseln mit `/api/dashboard` des Weight Trackers - das ist die
/// Auswahl der Kacheln im Gewicht-Tab.
struct DashboardTab: View {

    @State private var store = DashboardStore()
    @State private var logbook = LogbookStore()
    /// Das Strain-Fenster (Vertrag §5) - ein Blatt, keine Seite: es ist ein
    /// Blick in den Verlauf, von dem man gleich zurueck will.
    @State private var showingStrain = DashboardTab.opensStrain
    /// Das Morgen-Briefing (Vertrag §8.3) - angefordert nach dem Abgleich.
    @State private var briefing = BriefingStore()
    /// Der Chat gehoert dem Dashboard, nicht dem Blatt: eine laufende Antwort
    /// laeuft weiter, wenn es zugeht, und der Knopf zeigt, wenn sie da ist.
    @State private var chat = ChatStore()
    /// Der Knopf in der Leiste oeffnet ihn direkt; der Tipp auf „Deine Antwort
    /// ist da.“ und im Debug-Build `COCKPIT_TAB=chat` ueber den `Router`.
    @State private var showingChat = false
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
                        // Ganz unten: ein Rueckblick liest sich in Ruhe, die
                        // Karten des Tages und das Logbook bleiben, wo sie waren.
                        if let review = WeekReviewCardModel(store.review) {
                            WeekReviewCard(model: review)
                        }
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
            .sheet(isPresented: $showingStrain) { StrainSheet() }
            .sheet(isPresented: $showingChat) { ChatSheet(store: chat) }
            .toolbar {
                // Der Chat - nur, wo der Dienst ihn fuer diese Person freigeschaltet hat.
                if store.features?.chat == true {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingChat = true } label: {
                            // Gefuellt, solange eine Antwort ungesehen ist.
                            Image(systemName: chat.hasUnseenAnswer
                                  ? "bubble.left.and.text.bubble.right.fill"
                                  : "bubble.left.and.text.bubble.right")
                        }
                        .accessibilityLabel(chat.hasUnseenAnswer ? "Chat, neue Antwort" : "Chat")
                        .accessibilityIdentifier("chatButton")
                    }
                }
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
                // Runterwischen schreibt das Briefing aus dem aktuellen Stand neu (Felix, 11.11.).
                await afterSync(refreshBriefing: true)
            }
            .task {
                briefing.appeared()
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
                await afterSync()
            }
            // Welcher Tag im Logbook: neu, wenn das Dashboard erscheint, die App
            // zurueckkommt und um Mitternacht.
            .onAppear {
                logbook.followToday()
                briefing.appeared()
                openChatIfRequested()
            }
            .onDisappear { briefing.disappeared() }
            .onChange(of: router.chatRequests) { openChatIfRequested() }
            // Ein Weg fuehrt anderswohin (Stupser, Logbook-Erinnerung, Kachel):
            // ein offenes Blatt laege ueber dem Ziel.
            .onChange(of: router.dashboardSheetDismissals) {
                showingStrain = false
                showingChat = false
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                logbook.followToday()
                // Zurueck im Vordergrund: erst der Abgleich (laeuft schon einer,
                // wird er abgewartet), dann das Briefing und der Chat.
                guard router.selection == .dashboard else { return }
                Task {
                    await HealthSync.shared.syncIfDue()
                    await afterSync()
                }
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
                Task {
                    await store.load()
                    // Kam eine Nacht dazu, schreibt der Dienst das Briefing einmal neu.
                    await briefing.ensure(enabled: store.features?.briefing)
                }
            }
            .onChange(of: OfflineStatus.shared.pending) { before, after in
                if before > 0, after == 0 { Task { await store.load() } }
            }
        }
    }

    /// Im Debug-Build ueber `COCKPIT_TAB=strain`: das Dashboard samt offenem
    /// Strain-Fenster - fuer Bilder, tippen kann der Simulator nicht.
    private static var opensStrain: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "strain"
        #else
        return false
        #endif
    }

    /// Was nach dem Health-Abgleich dieses Oeffnens kommt (mit oder ohne
    /// Erfolg): das Briefing anfordern - vorher laege die Nacht von heute frueh
    /// noch nicht beim Dienst (Vertrag §8.3) - und nachsehen, ob im Chat eine
    /// Antwort wartet.
    private func afterSync(refreshBriefing: Bool = false) async {
        await briefing.ensure(enabled: store.features?.briefing, refresh: refreshBriefing)
        if store.features?.chat == true { await chat.load() }
    }

    /// Ein Tipp auf „Deine Antwort ist da.“ oeffnet den Chat - auch, wenn die
    /// Bitte vor dieser Ansicht kam (Kaltstart).
    private func openChatIfRequested() {
        guard router.takeChatRequest() else { return }
        // Zwei Blaetter zugleich zeigt SwiftUI nicht - das Strain-Fenster macht Platz.
        showingStrain = false
        showingChat = true
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
        // Ganz oben, nur der Text (Vertrag §5); ohne Text fehlt die Karte.
        if let text = briefing.text {
            BriefingCard(text: text, rewriting: briefing.rewriting)
        }
        if let recovery = store.recovery {
            NavigationLink(value: DashboardPage.recovery) {
                RecoveryCard(day: recovery)
            }
            .buttonStyle(.plain)
            // Anker fuer die UI-Tests - am Knopf, nicht an der Karte darin:
            // ein Container ist nie „hittable".
            .accessibilityIdentifier("recoveryCard")
        }
        // Ohne Strain heute und in der Woche fehlt die Karte (Vertrag §5) -
        // etwa ohne Uhr, oder solange der Dienst den Strain nicht kennt.
        if let strain = StrainCardModel(today: store.strain, week: store.strainWeek ?? [], on: .today()) {
            Button { showingStrain = true } label: {
                StrainCard(model: strain)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("strainCard")
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
                if let food = store.foodShown {
                    Button { router.showFoodToday() } label: {
                        FoodHalfCard(day: food, steps: store.steps, provisional: store.isFoodProvisional)
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("foodCard")
                }
            }
            // Beide Haelften gleich hoch, auch wenn eine eine Zeile mehr hat.
            .fixedSize(horizontal: false, vertical: true)
        }
        // Serien | Eichung (Vertrag §5). Die Eichung fehlt bei einem Dienst von
        // vor dem Monitor, die Serien, wo der Dienst sie nicht kennt.
        let calibration = store.energy.flatMap { $0.calibrationMonitor == nil ? nil : $0 }
        if store.streaks != nil || calibration != nil {
            HStack(alignment: .top, spacing: 12) {
                if let streaks = store.streaks {
                    Button { router.show(.friends) } label: { StreaksHalfCard(tile: streaks) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("streaksCard")
                }
                if let calibration {
                    CalibrationHalfCard(summary: calibration)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
