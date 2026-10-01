import SwiftUI

/// Felix' alte Habit-Liste aus der Fokus-App - in coHabit statt „Heute", wenn
/// im Profil „Klassische Liste" an ist.
///
/// Sieht aus und bedient sich wie der Habits-Tab bis 2026-09-30: Flamme mit
/// Zahl, rechts je Art ein Haken, ein Rueckfall-Knopf, der kcal-Stand, die
/// Schritte oder die Fokus-Zeit. Was es damals nicht gab, kommt aus coHabit:
/// das Beweisfoto-Blatt, die Detailseite, Offline-Leiste und Fehlerzeilen.
struct ClassicHabitsView: View {

    @State private var store = ClassicStore()
    @State private var showingEditor = false
    /// Das Habit, dessen letzte Tage gerade offen sind (Langdruck).
    @State private var historyHabitID: String?
    /// Die Zeile, die gerade gedrueckt wird - sie hebt sich leicht, wie beim
    /// Kontextmenue des Systems.
    @State private var pressedHabitID: String?
    /// Das Habit im Editor (Tipp auf den Namen, als Admin).
    @State private var editingHabit: ClassicHabit?
    /// Ein geteiltes Habit, das gewischt wurde - Verlassen will bestaetigt sein.
    @State private var leavingHabit: ClassicHabit?

    private var sync: CohabitSync { CohabitSync.shared }
    private var checkIns: CheckInController { CheckInController.shared }

    var body: some View {
        Group {
            if store.habits.isEmpty, store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if SyncLine.hasContent {
                SyncLine()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
        // Die untere Leiste von coHabit schwebt ueber der Liste - die letzte
        // Zeile muss sich darueber schieben lassen.
        .safeAreaInset(edge: .bottom, spacing: 0) { TabBarSpacer() }
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("addHabit")
            }
        }
        .sheet(isPresented: $showingEditor) {
            ClassicEditorSheet(store: store)
        }
        .sheet(item: Binding(
            get: { historyHabitID.map(HistoryTarget.init) },
            set: { historyHabitID = $0?.id })) { target in
            ClassicHistorySheet(store: store, habitID: target.id)
        }
        .sheet(item: $editingHabit) { habit in
            ClassicEditorSheet(store: store, editing: habit)
        }
        .refreshable { await store.load() }
        .task { await store.load() }
        // Eine Aenderung anderswo (Detailseite, Beweisfoto, Rueckkehr in den
        // Vordergrund) - die eigenen stehen schon drin.
        .onChange(of: DataBus.shared.revision) { _, revision in
            if revision != store.ownRevision { Task { await store.load() } }
        }
        // Ist der Postausgang leer geworden, weiss der Dienst jetzt mehr als
        // die Liste - also neu holen.
        .onChange(of: sync.flushCount) { Task { await store.load() } }
        // Kein Violett von coHabit: ohne Tint wie in der Fokus-App - Knoepfe
        // im Systemblau, die Leistenknoepfe (iOS 26) einfarbig. Ein
        // ausdrueckliches `.tint(.blue)` faerbte auch das „+" blau.
        .tint(nil as Color?)
    }

    private var list: some View {
        List {
            if let message = store.errorMessage {
                ErrorLine(message: message)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(store.habits) { habit in
                ClassicHabitRow(habit: habit,
                                isPending: sync.pendingClassic.contains(habit.id)
                                    || sync.pendingCheckins.contains(habit.id),
                                isBusy: store.preparingPhoto.contains(habit.id) || checkIns.busy.contains(habit.id),
                                toggle: { Task { await store.toggleToday(habit) } },
                                edit: { edit(habit) })
                // Langdruck: gleich die letzten Tage nachtragen - der Haken
                // von vorgestern, der Rueckfall von gestern. Ohne Menue
                // dazwischen, das war Felix ein Schritt zu viel - aber mit dem
                // Anheben und dem Tippen des Systemmenues, das ihm fehlte.
                .scaleEffect(pressedHabitID == habit.id ? 1.03 : 1)
                .animation(.easeOut(duration: 0.18), value: pressedHabitID)
                .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 12) {
                    guard habit.canBackfill else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    historyHabitID = habit.id
                } onPressingChanged: { pressing in
                    guard habit.canBackfill else { return }
                    pressedHabitID = pressing ? habit.id : nil
                }
                // An der Zeile, nicht an der Liste: unter iOS 26 ist die
                // Rueckfrage ein Popover, und sein Pfeil soll auf das Habit zeigen.
                .confirmationDialog("„\(habit.name)“ verlassen?", isPresented: Binding(
                    get: { leavingHabit?.id == habit.id },
                    set: { if !$0 { leavingHabit = nil } }
                ), titleVisibility: .visible) {
                    Button("Verlassen", role: .destructive) { Task { await store.delete(habit) } }
                    Button("Abbrechen", role: .cancel) {}
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if habit.shared {
                        // Ohne `role: .destructive`: die Rolle liesse die Zeile
                        // schon verschwinden, bevor die Rueckfrage beantwortet ist.
                        Button {
                            leavingHabit = habit
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                        .accessibilityLabel("Verlassen")
                        .accessibilityIdentifier("delete-\(habit.id)")
                    } else {
                        Button(role: .destructive) {
                            Task { await store.delete(habit) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Löschen")
                        .accessibilityIdentifier("delete-\(habit.id)")
                    }
                }
            }
            if store.habits.isEmpty, !store.isLoading, store.errorMessage == nil {
                Text("Noch keine Habits. Oben rechts eins anlegen.")
                    .foregroundStyle(.secondary)
            }
        }
        // Die Knoepfe in den Zeilen („Doch nicht", „Eintragen") im Systemblau
        // der Fokus-App - der zurueckgesetzte Tint unten wirkt nur auf die
        // Leistenknoepfe, sonst erbten sie das Violett von coHabit.
        .tint(.blue)
    }

    /// Tipp auf den Namen: als Admin der alte Editor, sonst die Detailseite in
    /// coHabit - dort steht, was ein Mitglied tun kann. Ziele und Challenges
    /// kennt der alte Editor nicht, sie gehen immer zur Detailseite.
    private func edit(_ habit: ClassicHabit) {
        if habit.opensEditor {
            editingHabit = habit
        } else {
            Router.shared.push(.cohabit(habit.id, .overview))
        }
    }
}

/// Nur eine Kennung, damit `.sheet(item:)` etwas Identifizierbares hat.
private struct HistoryTarget: Identifiable {
    let id: String
}

/// Ein Habit als Zeile - wie `HabitRow` der Fokus-App.
struct ClassicHabitRow: View {

    let habit: ClassicHabit
    /// Der Haken liegt ohne Netz im Postausgang - eine Uhr statt des Hakens.
    var isPending = false
    /// Das Beweisfoto-Blatt wird vorbereitet oder der Eintrag ist unterwegs.
    var isBusy = false
    let toggle: () -> Void
    /// Tipp auf Name oder Untertitel.
    var edit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if habit.kind.usesSummary {
                    metric
                } else {
                    flame
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.body.weight(.medium))
                    subtitle
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: edit)
                Spacer(minLength: 8)
                trailing
            }
            if habit.unavailable == nil && !habit.kind.usesSummary {
                ClassicRecentDots(recent: habit.recent, unit: habit.unit)
            }
            if habit.kind == .steps || habit.kind == .focus, let progress = habit.progress {
                ClassicProgressBar(fraction: progress.fraction, reached: habit.doneToday)
            }
            // Ziele haben einen Stand, Challenges nicht (dort zaehlt der Platz).
            if habit.kind.usesSummary, let progress = habit.summary?.progress {
                ClassicProgressBar(fraction: progress.fraction, reached: progress.fraction >= 1)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Links: die Flamme

    /// Flamme mit Zahl - wie bei Snapchat. Grau ohne Straehne, blass, wenn
    /// heute noch offen ist: die Straehne lebt, aber sie braucht dich.
    private var flame: some View {
        VStack(spacing: 0) {
            Image(systemName: habit.streak > 0 ? "flame.fill" : "flame")
                .font(.title2)
                .foregroundStyle(flameColor)
            Text("\(habit.streak)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(habit.streak > 0 ? .primary : .secondary)
                .accessibilityIdentifier("streak-\(habit.id)")
        }
        .frame(width: 40)
        .opacity(habit.unavailable == nil ? 1 : 0.3)
    }

    /// Ziel und Challenge an der Stelle der Flamme: Pokal bzw. Zielflagge mit
    /// der Kennzahl der neuen Liste darunter („#1", „30%").
    private var metric: some View {
        VStack(spacing: 0) {
            Image(systemName: habit.kind == .challenge ? "trophy.fill" : "flag.checkered")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(habit.summary?.headline.value ?? "")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("metric-\(habit.id)")
        }
        .frame(width: 40)
        .opacity(habit.unavailable == nil ? 1 : 0.3)
    }

    private var flameColor: Color {
        guard habit.streak > 0 else { return .secondary }
        return habit.atRisk ? .orange.opacity(0.45) : .orange
    }

    @ViewBuilder
    private var subtitle: some View {
        if let unavailable = habit.unavailable {
            Text(unavailable)
                .font(.caption)
                .foregroundStyle(.red)
        } else if habit.kind.usesSummary {
            Text(habit.summary?.listLine ?? habit.summary?.subline ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if habit.atRisk {
            Text("\(habit.streakText) · \(habit.openText)")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text(habit.streakText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rechts: je nach Art

    @ViewBuilder
    private var trailing: some View {
        if isPending {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityLabel("wartet auf Netz")
        } else {
            trailingByKind
        }
    }

    @ViewBuilder
    private var trailingByKind: some View {
        switch habit.kind {
        case .build:
            HStack(spacing: 10) {
                // Je Woche oder Monat: der Stand des Zeitraums neben dem
                // Haken von heute - „1/2" sagt, was noch fehlt.
                if habit.isPeriodic, let progress = habit.progress {
                    Text("\(progress.value)/\(progress.goal)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(progress.value >= progress.goal ? Color.green : Color.primary)
                        .accessibilityIdentifier("period-\(habit.id)")
                }
                Button(action: toggle) {
                    Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(habit.doneToday ? Color.green : Color.secondary)
                        // Unsichtbar, solange nichts laeuft - so bleibt der
                        // Platz des Hakens, und die Zeile springt nicht.
                        .opacity(isBusy ? 0 : 1)
                        .overlay { if isBusy { ProgressView() } }
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityValue(habit.doneToday ? "erledigt" : "offen")
                .accessibilityIdentifier("toggle-\(habit.id)")
            }
        case .quit:
            if habit.doneToday {
                Button("Rückfall", action: toggle)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityIdentifier("toggle-\(habit.id)")
            } else {
                // Der Rueckfall steht - der Knopf nimmt ihn zurueck, falls
                // er ein Fehlgriff war.
                Button("Doch nicht", action: toggle)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("toggle-\(habit.id)")
            }
        case .food:
            if let progress = habit.progress {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(habit.doneToday ? Color.green : Color.secondary)
                    Text(progress.kcalText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .steps:
            if let progress = habit.progress {
                Text(progress.stepsText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(habit.doneToday ? Color.green : Color.primary)
                    .accessibilityIdentifier("steps-\(habit.id)")
            }
        case .focus:
            if let progress = habit.progress {
                Text(progress.focusText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(habit.doneToday ? Color.green : Color.primary)
                    .accessibilityIdentifier("focus-\(habit.id)")
            }
        case .goal, .challenge:
            summaryTrailing
        case .unknown:
            EmptyView()
        }
    }

    /// Ziel und Challenge: „Eintragen" im Stil des alten „Rückfall"-Knopfs -
    /// was er oeffnet (Wert, +1, Beweisfoto), entscheidet `CheckInController`.
    /// Ohne Eintragen (etwa Health-Werte) ein Haken, wenn heute schon etwas steht.
    @ViewBuilder
    private var summaryTrailing: some View {
        if habit.summary?.canCheckIn == true {
            if isBusy {
                ProgressView()
            } else {
                Button("Eintragen", action: toggle)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(habit.summary?.checkInLabel ?? "Eintragen")
                    .accessibilityValue(habit.doneToday ? "heute eingetragen" : "offen")
                    .accessibilityIdentifier("toggle-\(habit.id)")
            }
        } else if habit.doneToday {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(Color.green)
                .accessibilityLabel("heute eingetragen")
        }
    }
}

/// Die letzten sieben Tage, Wochen oder Monate als Punkte, aelteste links.
struct ClassicRecentDots: View {

    let recent: [Bool]
    let unit: ClassicHabit.Unit

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(recent.enumerated()), id: \.offset) { index, done in
                Circle()
                    .fill(done ? Color.orange : Color.primary.opacity(0.12))
                    .frame(width: 8, height: 8)
                    // Der letzte Punkt ist heute bzw. diese Woche - ein Ring
                    // drumherum, damit man weiss, wo man steht.
                    .overlay {
                        if index == recent.count - 1 {
                            Circle().stroke(Color.orange, lineWidth: 1).padding(-2)
                        }
                    }
            }
        }
        .padding(.leading, 52)
        // Keine Beschriftung: „7 Wochen" las sich wie ein Ziel (Felix,
        // 2026-09-24). Die Punkte sind die letzten sieben Zeitraeume, der
        // Ring der laufende - das sagt die Reihe selbst.
        .accessibilityLabel(label)
    }

    private var label: String {
        switch unit {
        case .days:    "letzte 7 Tage"
        case .weeks:   "letzte 7 Wochen"
        case .months:  "letzte 7 Monate"
        case .windows: "letzte 7 Mal"
        }
    }
}

/// Die Leiste unter einem Schritte- oder Fokus-Habit.
struct ClassicProgressBar: View {

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
