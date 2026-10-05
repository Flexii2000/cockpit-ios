import SwiftUI

/// Angemeldet: die fuenf Bereiche. Sonst der Start mit „Link einfügen".
struct RootView: View {

    @Environment(\.scenePhase) private var scenePhase

    private var session: Session { Session.shared }

    var body: some View {
        ZStack(alignment: .top) {
            if isWidgetPreview {
                widgetPreview
            } else if session.isSignedIn {
                MainView()
                    .transition(.opacity)
            } else {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .environment(\.meId, session.meId)
        .tint(Ink.accent)
        .animation(.easeInOut(duration: 0.25), value: session.isSignedIn)
        .task {
            ToastWindow.install()
            await CohabitOutbox.shared.refreshStatus()
            #if DEBUG
            // Wie in den anderen Apps: fuer tools/pushtest.sh nach der
            // Erlaubnis fragen, ohne eine Kennung anzumelden.
            if ProcessInfo.processInfo.environment["COCKPIT_ASK_PUSH"] == "1" {
                await Notifications.requestPermission()
            }
            // COCKPIT_LINK=cohabit://… oeffnet einen Link beim Start - simctl
            // openurl zeigt bei eigenem Schema einen Dialog, den es nicht tippen
            // kann. Auch ohne Sitzung: dann meldet ein Setup-Link an.
            if let raw = ProcessInfo.processInfo.environment["COCKPIT_LINK"], let url = URL(string: raw) {
                Router.shared.open(url)
            }
            #endif
            guard session.isSignedIn else { return }
            await session.refreshMe()
            await Notifications.registerForPushIfAllowed()
            await PushRegistration.registerStoredDevice()
            await CohabitOutbox.shared.replay(using: session.api())
            await CohabitHealthSync.shared.syncIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.isSignedIn else { return }
            // Zurueck im Vordergrund heisst oft: zurueck im Netz.
            Task {
                await CohabitOutbox.shared.replay(using: session.api())
                await CohabitHealthSync.shared.syncIfDue()
                DataBus.shared.changed()
            }
        }
    }
}

extension RootView {
    private var isWidgetPreview: Bool {
        #if DEBUG
        WidgetPreviewScreen.isRequested
        #else
        false
        #endif
    }

    @ViewBuilder
    private var widgetPreview: some View {
        #if DEBUG
        WidgetPreviewScreen()
        #endif
    }
}

/// Die vier Bildschirme mit eigener Navigation und die untere Leiste.
struct MainView: View {

    /// „Klassische Liste" im Profil: dann zeigt „Heute" die alte Habit-Liste.
    @AppStorage(ClassicList.storageKey) private var classicList = false

    private var router: Router { Router.shared }
    private var checkIns: CheckInController { CheckInController.shared }

    var body: some View {
        @Bindable var router = router
        @Bindable var checkIns = checkIns
        ZStack(alignment: .bottom) {
            // Die System-Leiste haelt den Zustand jedes Bereichs (Scrollstand,
            // geladene Daten), gezeigt wird aber die eigene aus den Entwuerfen.
            TabView(selection: $router.tab) {
                Tab("Heute", systemImage: "house", value: MainTab.today) {
                    NavigationStack(path: $router.todayPath) {
                        Group {
                            if classicList {
                                ClassicHabitsView()
                            } else {
                                TodayView()
                            }
                        }
                        .withRoutes()
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
                Tab("Timeline", systemImage: "list.bullet.indent", value: MainTab.timeline) {
                    NavigationStack(path: $router.timelinePath) {
                        TimelineView().withRoutes()
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
                Tab("Statistik", systemImage: "chart.bar", value: MainTab.stats) {
                    NavigationStack(path: $router.statsPath) {
                        StatsView().withRoutes()
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
                Tab("Profil", systemImage: "person", value: MainTab.profile) {
                    NavigationStack(path: $router.profilePath) {
                        ProfileView().withRoutes()
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
            }
            if !router.isDeep {
                MainTabBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: router.isDeep)
        .fullScreenCover(isPresented: $router.showsCreate) {
            CreateFlowView()
        }
        .fullScreenCover(item: $router.invitation) { target in
            InvitationDialog(target: target)
                .presentationBackground(.clear)
        }
        .sheet(item: $checkIns.photoTarget) { target in
            PhotoCheckInSheet(target: target)
        }
        .sheet(item: $checkIns.valueTarget) { target in
            ValueEntrySheet(target: target)
        }
        .sheet(item: $checkIns.runTarget) { target in
            RunEntrySheet(target: target)
        }
        .confirmationDialog("Unterbrechung eintragen?", isPresented: Binding(
            get: { checkIns.breakTarget != nil },
            set: { if !$0 { checkIns.breakTarget = nil } }
        ), titleVisibility: .visible, presenting: checkIns.breakTarget) { target in
            Button("Unterbrechung heute eintragen", role: .destructive) {
                Task { await checkIns.submit(target, request: CheckinRequest(kind: .break, date: target.today)) }
            }
            if target.backfillFrom != nil {
                Button("Anderer Tag …") { checkIns.valueTarget = target }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

extension View {
    /// Alle Ziele, auf die ein Bildschirm schieben kann.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .cohabit(let id, let section):
                CohabitDetailView(cohabitId: id, initialSection: section)
            case .friends:
                FriendsView()
            case .notifications:
                NotificationSettingsView()
            case .typeColors:
                TypeColorsView()
            case .health:
                HealthConnectionView()
            case .archived:
                ArchivedView()
            case .appLinks:
                AppLinksView()
            case .editProfile:
                EditProfileView()
            case .export:
                ExportView()
            }
        }
    }
}

/// Die untere Leiste aus den Entwuerfen: eine weisse Kapsel, in der Mitte das
/// violette „+".
struct MainTabBar: View {

    private var router: Router { Router.shared }

    var body: some View {
        HStack(spacing: 0) {
            item(.today, symbol: "house", label: "Heute")
            item(.timeline, symbol: "list.bullet.indent", label: "Timeline")
            Button {
                router.showsCreate = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Ink.accent, in: Circle())
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Co-Habit anlegen")
            .accessibilityIdentifier("tab-new")
            item(.stats, symbol: "chart.bar", label: "Statistik")
            item(.profile, symbol: "person", label: "Profil")
        }
        .padding(.horizontal, 8)
        .frame(height: 72)
        .background(Ink.surface, in: Capsule())
        // Im Dunkeln traegt der Schatten nicht - die feine Linie hebt die
        // Leiste von Karten gleicher Farbe dahinter ab.
        .overlay(Capsule().strokeBorder(Ink.track, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 4)
    }

    private func item(_ tab: MainTab, symbol: String, label: String) -> some View {
        let selected = router.tab == tab
        return Button {
            if router.tab == tab {
                // Zweiter Tipp: zurueck an den Anfang, wie bei der System-Leiste.
                switch tab {
                case .today: router.todayPath = []
                case .timeline: router.timelinePath = []
                case .stats: router.statsPath = []
                case .profile: router.profilePath = []
                }
            }
            router.tab = tab
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Ink.ink)
                .frame(width: 50, height: 50)
                .background {
                    if selected { Circle().fill(Ink.accentSoft) }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tab-" + label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Die Meldung oben am Rand.
struct ToastView: View {
    private var toast: Toast { Toast.shared }

    var body: some View {
        if let message = toast.message, let detail = toast.detail {
            // Gross und klein: die Punkte eines Laufs mit ihrer Aufschluesselung.
            VStack(spacing: 2) {
                Text(message)
                    .font(.figure(30))
                Text(detail)
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.8)
            }
            .foregroundStyle(Ink.onInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Ink.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("toast")
            .zIndex(10)
        } else if let message = toast.message {
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(toast.isError ? Color.white : Ink.onInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(toast.isError ? Color(hex: 0xB3261E) : Ink.ink, in: Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("toast")
                .zIndex(10)
        }
    }
}

/// Platz unter dem Inhalt, damit die schwebende Leiste nichts verdeckt.
struct TabBarSpacer: View {
    var body: some View {
        Color.clear.frame(height: 96)
    }
}
