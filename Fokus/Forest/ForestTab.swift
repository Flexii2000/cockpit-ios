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
    /// „Eigene Dauer": ein Zahlenfeld fuer alles, was das Rad nicht hat.
    @State private var askingCustom = false
    @State private var customMinutes = ""
    @State private var choosingCategory = false

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
                        Button("Eigene Dauer …") { askingCustom = true }
                            .disabled(store.active != nil)
                        // Zum Durchspielen des Ablaufs - Schild, Meldung,
                        // Kurzbefehle - ohne eine halbe Stunde zu warten.
                        Button("Testbaum (20 s)") {
                            Task { await store.plantTest() }
                        }
                        .disabled(store.active != nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("forestMenu")
                }
            }
            .sheet(isPresented: $choosingCategory) {
                ForestCategorySheet(store: store)
            }
            // Apples eigenes Blatt statt eines selbstgebauten: der Picker ist
            // eine entfernte Ansicht eines Systemprozesses.
            .familyActivityPicker(isPresented: $showingWhitelist, selection: $store.whitelist)
            .alert("Eigene Dauer", isPresented: $askingCustom) {
                TextField("Minuten", text: $customMinutes)
                    .keyboardType(.numberPad)
                Button("Pflanzen") {
                    let value = Int(customMinutes.trimmingCharacters(in: .whitespaces)) ?? 0
                    customMinutes = ""
                    guard value >= SessionLength.customMinimum else { return }
                    Task { await store.plant(minutes: value) }
                }
                Button("Abbrechen", role: .cancel) { customMinutes = "" }
            }
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
                    Text(FocusMinutes.hours(choice) + " h").tag(choice)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .accessibilityIdentifier("sessionLength")
            Button {
                choosingCategory = true
            } label: {
                Label(store.category?.name ?? ForestCategorySheet.none, systemImage: "tag")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .accessibilityIdentifier("forestCategory")
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
    /// Tagesziel aus coHabit, sofern es eins gibt.
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
            return FocusMinutes.progress(store.todayMinutes, goal: goal)
        }
        let count = store.visibleSessions.count
        let trees = count == 1 ? "1 Baum" : "\(count) Bäume"
        return "\(trees) · \(FocusMinutes.hours(store.visibleMinutes)) h"
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
            if let category = session.categoryName {
                Label(category, systemImage: "tag")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sessionCategory")
            }
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

/// Ein Tag im Ausschnitt: Name, Baeume, Minuten - und darunter, wofuer,
/// sobald ein Baum des Tages eine Kategorie hat.
struct ForestDayRow: View {

    let day: ForestDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(day.sessions.count == 1 ? "1 Baum" : "\(day.sessions.count) Bäume")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(FocusMinutes.hours(day.minutes) + " h")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
            if let categories = FocusCategoryBreakdown.text(day.sessions) {
                Text(categories)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("dayCategories")
            }
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

/// Der Balken unter der Summe bei „Heute" - stand bis zum Umzug der Habits
/// nach coHabit im Habits-Tab und sieht hier unveraendert aus.
private struct ProgressBar: View {

    let fraction: Double
    let reached: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(reached ? Color.green : Color.orange)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 6)
        .padding(.leading, 52)
    }
}
