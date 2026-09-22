import FamilyControls
import SwiftUI

/// Der Wald: jede durchgestandene Fokus-Session ein Baum.
///
/// Oben der Baum, der gerade waechst (oder der Knopf, einen zu pflanzen),
/// darunter die Insel in 3D fuer den gewaehlten Ausschnitt - heute, Woche,
/// Monat, Jahr -, darunter die Summe und die Tage. Waehrend einer Session
/// gibt es hier nichts zu tun: kein Abbrechen, keine Verlaengerung - das war
/// die Vorgabe.
struct ForestTab: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ForestStore()
    @State private var minutes = 60
    @State private var showingWhitelist = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = store.errorMessage {
                        ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                    }
                    if let active = store.active {
                        RunningSessionCard(session: active)
                    } else {
                        plantCard
                    }

                    Picker("Zeitraum", selection: $store.range) {
                        ForEach(ForestRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForestSceneView(sessions: store.visibleSessions, active: store.active)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("forestScene")

                    summaryCard

                    if store.visibleDays.isEmpty, store.isLoading {
                        LoadingPlaceholder()
                    } else {
                        ForEach(store.visibleDays) { day in
                            ForestDayRow(day: day)
                        }
                    }
                }
                .padding(16)
                // Platz fuer die schwebende Tab-Leiste, wie im Gewicht-Tab.
                .padding(.bottom, 60)
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .habits) }
            .navigationTitle("Wald")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            // Erst die Erlaubnis, dann das Blatt: ohne sie
                            // bliebe Apples Auswahl leer.
                            Task { if await store.authorise() { showingWhitelist = true } }
                        } label: {
                            Text("Erlaubte Apps …")
                            // Der Schild gilt fuer alle Kategorien - auch fuer
                            // die Fokus-App selbst, so die Annahme.
                            Text("Fokus selbst mit auswählen")
                        }
                        // Was gesperrt ist, steht mit dem Pflanzen fest. Am
                        // laufenden Schild aenderte die Liste ohnehin nichts -
                        // sie soll waehrend einer Session aber auch nicht
                        // anfassbar sein (Felix, 2026-09-20).
                        .disabled(store.active != nil)
                        Toggle("Kurzbefehl „Fokus an“", isOn: $store.shortcutsEnabled)
                        Divider()
                        // Zum Durchspielen des Ablaufs - Schild, Meldung,
                        // Kurzbefehle - ohne eine halbe Stunde zu warten.
                        Button("Testbaum (20 s)") {
                            Task { await store.plantTest() }
                        }
                        .disabled(store.active != nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            // Apples eigenes Blatt statt eines selbstgebauten: der Picker ist
            // eine entfernte Ansicht eines Systemprozesses.
            .familyActivityPicker(isPresented: $showingWhitelist, selection: $store.whitelist)
            .refreshable { await store.load() }
            .task {
                await store.reconcile()
                await store.load()
            }
            // Zurueck im Vordergrund - vielleicht ist die Session inzwischen
            // vorbei (die Erweiterung hat den Schild dann schon weggenommen),
            // oder sie hat gerade erst begonnen und wartet auf ihren Schild.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.reconcile() } }
            }
            // Die Rueckkehr aus der Kurzbefehle-App (RootView waehlt den Tab,
            // hier landet die Rueckmeldung).
            .onOpenURL { url in store.handleCallback(url) }
            .onChange(of: OfflineStatus.shared.pending) { before, after in
                if before > 0, after == 0 { Task { await store.load() } }
            }
        }
    }

    private var plantCard: some View {
        VStack(spacing: 12) {
            Picker("Dauer", selection: $minutes) {
                ForEach(SessionLength.choices, id: \.self) { choice in
                    Text(HabitProgress.hours(choice) + " h").tag(choice)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .accessibilityIdentifier("sessionLength")
            Button {
                Task { await store.plant(minutes: minutes) }
            } label: {
                Label("Baum pflanzen", systemImage: "leaf.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityIdentifier("plantTree")
            if let note = store.screenTimeNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Die Summe des Ausschnitts; bei „Heute" dazu der Stand gegen das
    /// Tagesziel des Habits, sofern es eins gibt.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(store.range.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summaryText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(goalReached ? Color.green : Color.primary)
                    .accessibilityIdentifier("forestSummary")
            }
            if store.range == .today, let goal = store.dailyGoal, goal > 0 {
                ProgressBar(fraction: min(1, Double(store.todayMinutes) / Double(goal)),
                            reached: goalReached)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var goalReached: Bool {
        guard store.range == .today, let goal = store.dailyGoal else { return false }
        return store.todayMinutes >= goal
    }

    private var summaryText: String {
        if store.range == .today, let goal = store.dailyGoal {
            return HabitProgress(value: store.todayMinutes, goal: goal).focusText
        }
        let count = store.visibleSessions.count
        let trees = count == 1 ? "1 Baum" : "\(count) Bäume"
        return "\(trees) · \(HabitProgress.hours(store.visibleMinutes)) h"
    }
}

/// Der wachsende Baum: von klein beim Pflanzen bis voll am Ende, dazu die
/// Restzeit. Der Countdown zaehlt selbst (`Text(timerInterval:)`), der Baum
/// waechst alle dreissig Sekunden ein Stueck.
struct RunningSessionCard: View {

    let session: ActiveSession

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: session.start, by: 30)) { context in
                Image(systemName: "tree.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.green)
                    .scaleEffect(0.35 + 0.65 * session.growth(at: context.date), anchor: .bottom)
                    .frame(height: 110, alignment: .bottom)
                    .animation(.easeInOut(duration: 1), value: context.date)
            }
            Text(timerInterval: session.start...session.end, countsDown: true)
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .accessibilityIdentifier("sessionCountdown")
            Text("bis \(Self.clock.string(from: session.end))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Ein Tag im Ausschnitt: Name, Baeume, Minuten.
struct ForestDayRow: View {

    let day: ForestDay

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(day.sessions.count == 1 ? "1 Baum" : "\(day.sessions.count) Bäume")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(HabitProgress.hours(day.minutes) + " h")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        let today = CalendarDate.today()
        if day.day == today { return "Heute" }
        if let yesterday = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1,
                                                                 to: today.startOfDay()),
           day.day == CalendarDate(date: yesterday) {
            return "Gestern"
        }
        return Self.dayFormatter.string(from: day.day.startOfDay())
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE, dd.MM.yy"
        return formatter
    }()
}
