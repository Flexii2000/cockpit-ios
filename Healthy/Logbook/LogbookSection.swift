import SwiftUI

/// Das Logbook im Dashboard, unter den Halbkarten Gewicht | kcal (Vertrag
/// §4.2, Felix 12.10.: „direkt im Dashboard, bedienbarer, im Zweifel wie
/// Whoop“).
///
/// Jeder Tipp speichert: Ja/Nein sofort, der Zaehler nach einer halben Sekunde
/// Ruhe. Eine offene Zeile ist nur umrandet - offen heisst „unbekannt“, nicht
/// „nein“. Die Verhaltensweisen selbst richtet man im Blatt ein; das ist nichts
/// Taegliches.
struct LogbookSection: View {

    let store: LogbookStore
    @State private var showingBehaviors = false
    /// Die Zeile, deren Zahl gerade eingetippt wird.
    @State private var editing: Behavior?
    @State private var amountText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = store.error {
                ErrorBanner(message: error, isAccessProblem: store.accessProblem)
            }
            if let overview = store.overview {
                if overview.active.isEmpty {
                    Button("Verhalten anlegen") { showingBehaviors = true }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    dayRow
                    VStack(spacing: 0) {
                        ForEach(Array(overview.active.enumerated()), id: \.element.id) { index, behavior in
                            if index > 0 { Divider() }
                            LogbookRow(store: store, behavior: behavior) { edit(behavior) }
                        }
                    }
                }
            } else if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .dashboardCard()
        .sheet(isPresented: $showingBehaviors) { LogbookBehaviorsSheet(store: store) }
        .alert(editing?.name ?? "", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } })) {
            TextField(editing?.unit ?? "Menge", text: $amountText)
                .keyboardType(.decimalPad)
            Button("Abbrechen", role: .cancel) { editing = nil }
            Button("Fertig") {
                if let behavior = editing, !store.enter(behavior, text: amountText) {
                    NoticeCenter.shared.show("Eine Zahl von 0 bis 10.000, bitte.")
                }
                editing = nil
            }
        }
    }

    private func edit(_ behavior: Behavior) {
        amountText = store.value(behavior).map(LogbookFormat.amount) ?? ""
        editing = behavior
    }

    private var header: some View {
        HStack {
            Text("Logbook").font(.headline)
            Spacer(minLength: 8)
            if store.overview != nil {
                Button {
                    showingBehaviors = true
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 32, height: 28)
                }
                .accessibilityLabel("Verhalten")
            }
        }
    }

    /// „‹ [Gestern • | Heute]“ - weiter zurueck nur ueber ‹, keine Leiste.
    private var dayRow: some View {
        HStack(spacing: 8) {
            Button { store.step(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .disabled(store.day <= store.earliestDay)
            .accessibilityLabel("Tag davor")
            if store.day >= store.yesterday {
                LogbookDaySwitch(day: store.day, yesterday: store.yesterday, today: store.today,
                                 yesterdayOpen: store.isYesterdayOpen) { store.show($0) }
            } else {
                Text(Self.title(of: store.day))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                Button { store.step(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Tag danach")
            }
        }
    }

    /// „Mo., 05.10.“ - fuer die Tage vor gestern.
    static func title(of day: CalendarDate) -> String {
        dayFormat.string(from: day.startOfDay())
    }

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EE, dd.MM."
        return formatter
    }()
}

/// „Gestern | Heute“ wie ein Segment-Schalter, aber mit einem Punkt an
/// „Gestern“, solange gestern offen ist.
private struct LogbookDaySwitch: View {

    let day: CalendarDate
    let yesterday: CalendarDate
    let today: CalendarDate
    let yesterdayOpen: Bool
    let select: (CalendarDate) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment("Gestern", date: yesterday, dot: yesterdayOpen)
            segment("Heute", date: today, dot: false)
        }
        .padding(2)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    /// Wie beim System-Segmentschalter: hell weiss, dunkel ein helleres Grau als
    /// die Leiste - sonst verschwindet die Wahl auf der dunklen Karte.
    private static let selectedFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? .systemGray2 : .white
    })

    private func segment(_ title: String, date: CalendarDate, dot: Bool) -> some View {
        let selected = day == date
        return Button { select(date) } label: {
            HStack(spacing: 5) {
                Text(title)
                if dot {
                    Circle()
                        .fill(Tone.warn.color)
                        .frame(width: 6, height: 6)
                }
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background {
                if selected {
                    Capsule()
                        .fill(Self.selectedFill)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dot ? "\(title), offen" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Eine Verhaltensweise: Ja/Nein oder − Zahl +.
private struct LogbookRow: View {

    let store: LogbookStore
    let behavior: Behavior
    let editAmount: () -> Void

    var body: some View {
        let value = store.value(behavior)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(behavior.name)
                    .font(.body)
                    .lineLimit(2)
                if let unit = behavior.unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.isWaiting(behavior) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("wartet auf Netz")
            }
            Spacer(minLength: 8)
            if behavior.unit == nil {
                answers(value)
            } else {
                counter(value)
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: value)
        .contextMenu {
            if value != nil {
                Button("Zurücksetzen", systemImage: "arrow.uturn.backward") { store.reset(behavior) }
            }
        }
    }

    private func answers(_ value: Double?) -> some View {
        HStack(spacing: 6) {
            LogbookAnswerButton(title: "Nein", selected: value == 0) { store.answer(behavior, yes: false) }
                .accessibilityLabel("\(behavior.name): Nein")
                .accessibilityIdentifier("logbook-no-\(behavior.id)")
            LogbookAnswerButton(title: "Ja", selected: value == 1) { store.answer(behavior, yes: true) }
                .accessibilityLabel("\(behavior.name): Ja")
                .accessibilityIdentifier("logbook-yes-\(behavior.id)")
        }
    }

    private func counter(_ value: Double?) -> some View {
        HStack(spacing: 4) {
            LogbookStepButton(symbol: "minus") { store.step(behavior, by: -1) }
                .accessibilityLabel("\(behavior.name): weniger")
                .accessibilityIdentifier("logbook-minus-\(behavior.id)")
            Button(action: editAmount) {
                Text(value.map(LogbookFormat.amount) ?? "–")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(value == nil ? .secondary : .primary)
                    .frame(minWidth: 44, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(behavior.name): \(value.map(LogbookFormat.amount) ?? "offen")")
            .accessibilityIdentifier("logbook-amount-\(behavior.id)")
            LogbookStepButton(symbol: "plus") { store.step(behavior, by: 1) }
                .accessibilityLabel("\(behavior.name): mehr")
                .accessibilityIdentifier("logbook-plus-\(behavior.id)")
        }
    }
}

/// Offen nur umrandet, gewaehlt gefuellt - Ja wie Nein in derselben Farbe:
/// keine Antwort ist hier gut oder schlecht.
private struct LogbookAnswerButton: View {

    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .frame(minWidth: 54, minHeight: 34)
                .background {
                    if selected {
                        Capsule().fill(Color.accentColor)
                    } else {
                        Capsule().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LogbookStepButton: View {

    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Circle().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
