import FamilyControls
import SwiftUI

/// Der Wald: jede durchgestandene Fokus-Session ein Baum.
///
/// Oben der Baum, der gerade waechst (oder der Knopf, einen zu pflanzen),
/// darunter der heutige Stand gegen das Tagesziel, darunter der Wald - Tag
/// fuer Tag, neueste zuerst. Waehrend einer Session gibt es hier nichts zu
/// tun: kein Abbrechen, keine Verlaengerung - das war die Vorgabe.
struct ForestTab: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ForestStore()
    @State private var minutes = 60
    @State private var showingWhitelist = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let message = store.errorMessage {
                        ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                    }
                    if let active = store.active {
                        RunningSessionCard(session: active)
                    } else {
                        plantCard
                    }
                    todayCard
                    if store.days.isEmpty {
                        if store.isLoading {
                            LoadingPlaceholder()
                        } else {
                            Text("Noch kein Baum.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(store.days) { day in
                            ForestDayView(day: day)
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
                        Toggle("Kurzbefehle „Fokus an/aus“", isOn: $store.shortcutsEnabled)
                        Divider()
                        // Zum Durchspielen des Ablaufs - Schild, Meldung,
                        // Baum, Habit - ohne eine halbe Stunde zu warten.
                        Button("Testbaum (1 min)") {
                            Task { await store.plant(minutes: SessionLength.test) }
                        }
                        .disabled(store.active != nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            // Apples eigenes Blatt statt eines selbstgebauten: der Picker ist
            // eine entfernte Ansicht eines Systemprozesses, und in einem
            // eigenen Sheet blieb er auf dem Geraet leer (2026-09-20).
            .familyActivityPicker(isPresented: $showingWhitelist, selection: $store.whitelist)
            .refreshable { await store.load() }
            .task {
                await store.reconcile()
                await store.load()
            }
            // Zurueck im Vordergrund - vielleicht ist die Session inzwischen
            // vorbei (die Erweiterung hat den Schild dann schon weggenommen).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.reconcile() } }
            }
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

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Heute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(todayText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(goalReached ? Color.green : Color.primary)
                    .accessibilityIdentifier("todayFocus")
            }
            if let goal = store.dailyGoal, goal > 0 {
                ProgressBar(fraction: min(1, Double(store.todayMinutes) / Double(goal)),
                            reached: goalReached)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var goalReached: Bool {
        if let goal = store.dailyGoal { return store.todayMinutes >= goal }
        return false
    }

    private var todayText: String {
        if let goal = store.dailyGoal {
            return HabitProgress(value: store.todayMinutes, goal: goal).focusText
        }
        return HabitProgress.hours(store.todayMinutes) + " h"
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

/// Ein Tag im Wald: Kopfzeile mit Summe, darunter die Baeume auf dem Boden.
struct ForestDayView: View {

    let day: ForestDay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(HabitProgress.hours(day.minutes) + " h")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 2)],
                      alignment: .leading, spacing: 2) {
                ForEach(day.sessions) { session in
                    TreeView(minutes: session.minutes)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .background(alignment: .bottom) {
                // Der Boden: ein Streifen unter den Staemmen.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brown.opacity(0.25))
                    .frame(height: 6)
            }
        }
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
        formatter.dateFormat = "EEE, dd.MM."
        return formatter
    }()
}

/// Ein Baum - je laenger die Session, desto groesser und dunkler.
struct TreeView: View {

    let minutes: Int

    var body: some View {
        let size = TreeSize(minutes: minutes)
        Image(systemName: "tree.fill")
            .font(.system(size: size.pointSize))
            .foregroundStyle(Self.color(size))
            .frame(width: 46, height: 52, alignment: .bottom)
            .accessibilityLabel("\(minutes) Minuten")
    }

    private static func color(_ size: TreeSize) -> Color {
        switch size {
        case .sapling: Color(red: 0.55, green: 0.78, blue: 0.45)
        case .young:   Color(red: 0.35, green: 0.68, blue: 0.35)
        case .grown:   Color(red: 0.20, green: 0.56, blue: 0.28)
        case .old:     Color(red: 0.10, green: 0.42, blue: 0.22)
        }
    }
}
