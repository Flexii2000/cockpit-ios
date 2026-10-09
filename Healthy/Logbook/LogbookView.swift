import SwiftUI

/// Das Logbook: je Tag eintragen, was man getan hat, und sehen, was davon mit
/// der Recovery des naechsten Morgens zusammenhaengt (Whoop-Prinzip, Felix
/// 09.10.).
///
/// Eine Seite im Dashboard, kein Tab. Oben der Tag - gestern bis vor 14
/// Tagen - mit einem Schalter je Verhaltensweise und „Speichern": erst dann
/// gilt der Tag als ausgefuellt, und was nicht angetippt ist, als „nein".
/// Darunter die Effekte, gerechnet im Weight Tracker.
struct LogbookView: View {

    @State private var store = LogbookStore()
    @State private var showingBehaviors = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = store.error {
                    ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                }
                if let overview = store.overview {
                    if overview.active.isEmpty {
                        emptyState
                    } else {
                        dayCard(overview)
                    }
                    effects
                } else if store.isLoading {
                    LoadingPlaceholder()
                }
            }
            .padding(16)
            // Platz fuer die schwebende Tab-Leiste, wie im Gewicht-Tab.
            .padding(.bottom, 60)
        }
        .navigationTitle("Logbook")
        .toolbar {
            if store.overview != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingBehaviors = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Verhalten")
                }
            }
        }
        .sheet(isPresented: $showingBehaviors) { LogbookBehaviorsSheet(store: store) }
        .refreshable { await store.load() }
        .task { await store.load() }
        // Ist der Postausgang leer geworden, ist ein wartender Tag beim Dienst.
        .onChange(of: OfflineStatus.shared.pending) { before, after in
            if before > 0, after == 0 { Task { await store.load() } }
        }
    }

    // MARK: - Leer

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Button("Verhalten anlegen") { showingBehaviors = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Tag

    private func dayCard(_ overview: LogbookOverview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { store.step(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .disabled(store.day <= store.earliestDay)
                .accessibilityLabel("Tag davor")
                Spacer()
                HStack(spacing: 6) {
                    Text(Self.title(of: store.day))
                        .font(.headline)
                    stateIcon
                }
                Spacer()
                Button { store.step(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .disabled(store.day >= store.latestDay)
                .accessibilityLabel("Tag danach")
            }

            ForEach(overview.active) { behavior in
                LogbookBehaviorRow(behavior: behavior, entry: entryBinding(for: behavior))
            }

            Button {
                Task { await store.save() }
            } label: {
                Text("Speichern")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canSave)
            .accessibilityIdentifier("logbookSave")
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Haken: beim Dienst. Uhr: wartet im Postausgang. Sonst nichts.
    @ViewBuilder
    private var stateIcon: some View {
        switch store.dayState {
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Tone.good.color)
                .accessibilityLabel("Gespeichert")
                .accessibilityIdentifier("logbookSaved")
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(Tone.warn.color)
                .accessibilityLabel("Wartet auf Netz")
        case .open:
            EmptyView()
        }
    }

    private func entryBinding(for behavior: Behavior) -> Binding<LogbookEntry> {
        Binding(
            get: { store.entries[behavior.id] ?? LogbookEntry(isOn: false, amount: "") },
            set: { store.entries[behavior.id] = $0 })
    }

    /// „Gestern", „Vorgestern", sonst „Mo., 05.10.".
    static func title(of day: CalendarDate) -> String {
        switch day.daysFromToday() {
        case -1: "Gestern"
        case -2: "Vorgestern"
        default: dayFormat.string(from: day.startOfDay())
        }
    }

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EE, dd.MM."
        return formatter
    }()

    // MARK: - Effekte

    @ViewBuilder
    private var effects: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Effekte").font(.headline)
                Spacer()
                // Unter 14 Morgen mit Score rechnet der Dienst nichts - wie weit
                // es noch ist, sagt die Zahl.
                if let insights = store.insights, !insights.hasEnoughNights {
                    Text("\(insights.nightsWithScore)/\(LogbookInsights.requiredNights) Morgen")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Zeitraum", selection: Binding(
                get: { store.period },
                set: { period in Task { await store.select(period: period) } })) {
                ForEach(LogbookAPI.periods, id: \.self) { days in
                    Text("\(days) Tage").tag(days)
                }
            }
            .pickerStyle(.segmented)

            if let insights = store.insights {
                ForEach(insights.unavailableSources, id: \.self) { source in
                    Label("\(source) nicht erreichbar", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Tone.warn.color)
                }
                ForEach(insights.evaluated) { predictor in
                    LogbookEffectRow(predictor: predictor)
                }
                if !insights.notEvaluated.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(insights.notEvaluated) { predictor in
                                LogbookPendingRow(predictor: predictor)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Zu wenig Daten (\(insights.notEvaluated.count))")
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

/// Ein Schalter je Verhaltensweise, mit Einheit dazu das Mengenfeld.
private struct LogbookBehaviorRow: View {

    let behavior: Behavior
    @Binding var entry: LogbookEntry

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Toggle(behavior.name, isOn: $entry.isOn)
            if let unit = behavior.unit, entry.isOn {
                HStack(spacing: 6) {
                    TextField("Menge", text: $entry.amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .textFieldStyle(.roundedBorder)
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// „Name  +8,1 %-Pkt **" und darunter „[+3,2; +13,0] · 41 ja · 37 nein".
struct LogbookEffectRow: View {

    let predictor: Predictor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LogbookSourceIcon(source: predictor.source)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(predictor.name)
                        .font(.subheadline.weight(.medium))
                    if let perUnit = LogbookFormat.perUnit(predictor) {
                        Text(perUnit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let effect = LogbookFormat.effectLine(predictor) {
                        Text(effect)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(color)
                            .fixedSize()
                    }
                }
                Text(LogbookFormat.detail(predictor))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Farbe nur fuer, was nach Holm traegt - ein Effekt ohne Stern ist noch
    /// kein Befund.
    private var color: Color {
        guard let effect = predictor.effect, !LogbookFormat.stars(predictor.pAdjusted).isEmpty else {
            return .primary
        }
        return effect >= 0 ? Tone.good.color : Tone.warn.color
    }
}

/// Eine Zeile ohne Effekt: wie weit sie noch ist („3/5 ja · 5/5 nein").
private struct LogbookPendingRow: View {

    let predictor: Predictor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LogbookSourceIcon(source: predictor.source)
            Text(predictor.name)
                .font(.subheadline)
            if let perUnit = LogbookFormat.perUnit(predictor) {
                Text(perUnit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(LogbookFormat.notEvaluated(predictor))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Woher eine Zeile stammt, als kleines Symbol: eigenes Verhalten, Co-Habit
/// oder ein Wert aus Healthy.
struct LogbookSourceIcon: View {

    let source: PredictorSource

    var body: some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 16)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch source {
        case .logbook: "book.closed"
        case .cohabit: Backend.cohabit.systemImage
        case .healthy: "heart"
        case .unknown: "circle"
        }
    }

    private var label: String {
        switch source {
        case .logbook: "Logbook"
        case .cohabit: "coHabit"
        case .healthy: "Healthy"
        case .unknown: ""
        }
    }
}
