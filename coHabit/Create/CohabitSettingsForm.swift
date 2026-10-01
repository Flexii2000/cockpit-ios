import SwiftUI

/// Die Einstellungen eines Co-Habits (Entwurf S. 13, Vertrag §5.2.13) - fuer
/// Anlegen Schritt 2 und fuers Bearbeiten.
struct CohabitSettingsForm: View {
    @Binding var config: CohabitConfig
    /// `me.sources` - nur wer eine Quelle hat, bekommt „Automatisch".
    let sources: [String]
    let editing: Bool

    @State private var showsZones = false

    var body: some View {
        VStack(spacing: 14) {
            nameCard
            switch config.type {
            case .streak: rhythmCard
            case .abstinence: abstinenceCard
            case .goal: goalCard
            case .challenge: challengeCard
            }
            settingsCard
        }
        .sheet(isPresented: $showsZones) {
            TimeZonePicker(selection: $config.timezone)
        }
    }

    // MARK: - Name und Farbe

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Name")
            InputField(placeholder: "Name", text: Binding(
                get: { config.name },
                set: { config.name = String($0.prefix(40)) }), identifier: "createName")
            FieldLabel(text: "Farbe")
            HStack(spacing: 10) {
                ForEach(PaletteKey.allCases) { key in
                    Button {
                        config.color = key
                    } label: {
                        Circle()
                            .fill(key.colors.surface)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(Ink.ink, lineWidth: config.color == key ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key.title)
                    .accessibilityAddTraits(config.color == key ? .isSelected : [])
                }
            }
        }
        .card(padding: 16)
    }

    // MARK: - Streak

    private enum RhythmChoice: String, CaseIterable {
        case daily = "DAILY", weekdays = "WEEKDAYS", week = "TIMES_PER_WEEK", month = "TIMES_PER_MONTH",
             interval = "INTERVAL", auto = "AUTO"

        var title: String {
            switch self {
            case .daily: "Täglich"
            case .weekdays: "Wochentage"
            case .week: "pro Woche"
            case .month: "pro Monat"
            case .interval: "Intervall"
            case .auto: "Automatisch"
            }
        }
    }

    private var rhythmChoice: RhythmChoice {
        if config.auto != nil { return .auto }
        return RhythmChoice(rawValue: config.streak?.rhythm.kind ?? "DAILY") ?? .daily
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Rhythmus")
            FlowLayout(spacing: 8) {
                ForEach(RhythmChoice.allCases.filter { $0 != .auto || (!sources.isEmpty && (!editing || config.auto != nil)) },
                        id: \.self) { choice in
                    choiceChip(choice.title, selected: rhythmChoice == choice) { select(choice) }
                        .disabled(editing && (choice == .auto) != (config.auto != nil))
                }
            }
            switch rhythmChoice {
            case .weekdays:
                weekdayPicker
            case .week:
                timesStepper(unit: "pro Woche", range: 1...7)
            case .month:
                timesStepper(unit: "pro Monat", range: 1...31)
            case .interval:
                let days = config.streak?.rhythm.days ?? 2
                StepperCapsule(text: "alle \(days) Tage", canDecrease: days > 2, canIncrease: days < 30,
                               decrease: { config.streak?.rhythm.days = days - 1 },
                               increase: { config.streak?.rhythm.days = days + 1 })
            case .auto:
                autoPicker
            case .daily:
                EmptyView()
            }
        }
        .card(padding: 16)
    }

    private func select(_ choice: RhythmChoice) {
        if config.streak == nil { config.streak = .init(rhythm: .daily, groupStreak: false) }
        switch choice {
        case .auto:
            let source = sources.first ?? "FOOD"
            applyAuto(source)
        default:
            config.auto = nil
            var rhythm = CohabitConfig.Rhythm(kind: choice.rawValue)
            switch choice {
            case .weekdays: rhythm.weekdays = config.streak?.rhythm.weekdays ?? [1, 3, 5]
            case .week: rhythm.times = min(7, config.streak?.rhythm.times ?? 3)
            case .month: rhythm.times = config.streak?.rhythm.times ?? 2
            case .interval: rhythm.days = config.streak?.rhythm.days ?? 2
            default: break
            }
            config.streak?.rhythm = rhythm
        }
    }

    private func applyAuto(_ source: String) {
        config.auto = CohabitConfig.Auto(source: source,
                                         weeklyStepGoal: source == "STEPS_WEEKLY" ? (config.auto?.weeklyStepGoal ?? 70_000) : nil,
                                         focusMinutesGoal: source == "FOCUS" ? (config.auto?.focusMinutesGoal ?? 240) : nil)
        // Wie die bisherigen automatischen Habits (Vertrag §7.1): Schritte
        // zaehlen je Woche, Essen und Fokus je Tag.
        config.streak?.rhythm = source == "STEPS_WEEKLY" ? .init(kind: "TIMES_PER_WEEK", times: 1) : .daily
        config.tracking = .check
        config.photoRequired = false
        config.health = nil
    }

    private var weekdayPicker: some View {
        let names = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let selected = Set(config.streak?.rhythm.weekdays ?? [])
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = selected.contains(day)
                Button {
                    var days = selected
                    if on { days.remove(day) } else { days.insert(day) }
                    config.streak?.rhythm.weekdays = days.sorted()
                } label: {
                    Text(names[day - 1])
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(on ? Ink.onInk : Ink.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(on ? Ink.ink : Ink.track, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func timesStepper(unit: String, range: ClosedRange<Int>) -> some View {
        let times = config.streak?.rhythm.times ?? range.lowerBound
        return StepperCapsule(text: "\(times)× \(unit)",
                              canDecrease: times > range.lowerBound, canIncrease: times < range.upperBound,
                              decrease: { config.streak?.rhythm.times = times - 1 },
                              increase: { config.streak?.rhythm.times = times + 1 })
    }

    private var autoPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(sources, id: \.self) { source in
                    choiceChip(Self.sourceTitle(source), selected: config.auto?.source == source) {
                        applyAuto(source)
                    }
                    .disabled(editing)
                }
            }
            if config.auto?.source == "STEPS_WEEKLY" {
                let goal = config.auto?.weeklyStepGoal ?? 70_000
                StepperCapsule(text: "\(goal.formatted(.number.locale(Locale(identifier: "de_DE")))) Schritte / Woche",
                               canDecrease: goal > 5_000, canIncrease: goal < 500_000,
                               decrease: { config.auto?.weeklyStepGoal = goal - 5_000 },
                               increase: { config.auto?.weeklyStepGoal = goal + 5_000 })
            }
            if config.auto?.source == "FOCUS" {
                let minutes = config.auto?.focusMinutesGoal ?? 240
                StepperCapsule(text: String(format: "%d:%02d h am Tag", minutes / 60, minutes % 60),
                               canDecrease: minutes > 15, canIncrease: minutes < 960,
                               decrease: { config.auto?.focusMinutesGoal = minutes - 15 },
                               increase: { config.auto?.focusMinutesGoal = minutes + 15 })
            }
        }
    }

    nonisolated static func sourceTitle(_ source: String) -> String {
        switch source {
        case "FOOD": "Track food"
        case "STEPS_WEEKLY": "Schritte / Woche"
        case "FOCUS": "Fokus-Zeit"
        default: source
        }
    }

    // MARK: - Abstinenz

    private var abstinenceCard: some View {
        FormCard {
            ToggleRow(title: "Gruppenmodus", isOn: Binding(
                get: { config.abstinence?.groupMode ?? false },
                set: { config.abstinence = .init(groupMode: $0) }))
        }
    }

    // MARK: - Ziel

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(text: "Zielwert")
            NumberInput(placeholder: "Zielwert", value: Binding(
                get: { config.goal?.target },
                set: { if let value = $0 { config.goal?.target = value } }), unit: config.tracking.unit ?? "COUNT",
                identifier: "goalTarget")
            FieldLabel(text: "Zählt")
            CapsuleSegments(options: [("ENTRIES", "Einträge", nil), ("AMOUNT", "Menge", nil)],
                            selection: Binding(
                                get: { config.goal?.counting ?? "ENTRIES" },
                                set: { counting in
                                    config.goal?.counting = counting
                                    config.tracking = counting == "AMOUNT"
                                        ? .init(mode: "VALUE", unit: config.tracking.unit ?? "COUNT") : .check
                                }), fill: Ink.track)
            if config.goal?.counting == "AMOUNT" {
                unitChips
            }
            DatePicker("Bis", selection: dateBinding(\.goal!.deadline), in: Date()..., displayedComponents: .date)
                .font(.system(size: 17, weight: .bold))
                .environment(\.locale, Locale(identifier: "de_DE"))
            FieldLabel(text: "Modus")
            CapsuleSegments(options: [("INDIVIDUAL", "Einzel", nil), ("TEAM", "Team", nil)],
                            selection: Binding(get: { config.goal?.mode ?? "TEAM" },
                                               set: { config.goal?.mode = $0 }), fill: Ink.track)
        }
        .card(padding: 16)
    }

    // MARK: - Challenge

    private var challengeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Start", selection: dateBinding(\.challenge!.start), displayedComponents: .date)
                .font(.system(size: 17, weight: .bold))
                .disabled(editing)
            DatePicker("Ende", selection: dateBinding(\.challenge!.end),
                       in: (config.challenge?.start.startOfDay() ?? Date())..., displayedComponents: .date)
                .font(.system(size: 17, weight: .bold))
            FieldLabel(text: "Wertung")
            FlowLayout(spacing: 8) {
                ForEach([("MOST_ENTRIES", "Meiste Einträge"), ("HIGHEST_SUM", "Höchste Summe"),
                         ("FIRST_TO_TARGET", "Wer zuerst …")], id: \.0) { scoring, title in
                    choiceChip(title, selected: config.challenge?.scoring == scoring) {
                        config.challenge?.scoring = scoring
                        config.tracking = scoring == "MOST_ENTRIES" ? .check
                            : .init(mode: "VALUE", unit: config.tracking.unit ?? "COUNT")
                    }
                }
            }
            if config.challenge?.scoring != "MOST_ENTRIES" {
                unitChips
            }
            if config.challenge?.scoring == "FIRST_TO_TARGET" {
                FieldLabel(text: "Zielwert")
                NumberInput(placeholder: "Zielwert", value: Binding(
                    get: { config.challenge?.target },
                    set: { config.challenge?.target = $0 }), unit: config.tracking.unit ?? "COUNT",
                    identifier: "challengeTarget")
            }
            FieldLabel(text: "Einsatz")
            InputField(placeholder: "Verlierer kocht für alle", text: Binding(
                get: { config.challenge?.stake ?? "" },
                set: { config.challenge?.stake = $0.isEmpty ? nil : String($0.prefix(80)) }), identifier: "challengeStake")
            FieldLabel(text: "Wiederholung")
            CapsuleSegments(options: [("NONE", "Einmal", nil), ("WEEKLY", "Wöchentlich", nil), ("MONTHLY", "Monatlich", nil)],
                            selection: Binding(get: { config.challenge?.recurrence ?? "NONE" },
                                               set: { config.challenge?.recurrence = $0 }), fill: Ink.track)
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
        .card(padding: 16)
    }

    private var unitChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Self.units, id: \.0) { unit, title in
                choiceChip(title, selected: config.tracking.unit == unit) {
                    config.tracking = .init(mode: "VALUE", unit: unit)
                }
            }
        }
    }

    static let units = [("COUNT", "Anzahl"), ("MINUTES", "Minuten"), ("KM", "km"), ("STEPS", "Schritte"),
                        ("KCAL", "kcal")]

    // MARK: - Weitere Einstellungen

    private var settingsCard: some View {
        FormCard {
            if config.auto == nil {
                ToggleRow(title: "Beweisfoto-Pflicht", isOn: $config.photoRequired, identifier: "photoRequired")
                FormDivider()
            }
            if config.type == .streak && config.auto == nil {
                ToggleRow(title: "Mit Wert erfassen", isOn: Binding(
                    get: { config.tracking.isValue },
                    set: { config.tracking = $0 ? .init(mode: "VALUE", unit: config.tracking.unit ?? "COUNT") : .check }))
                if config.tracking.isValue {
                    unitChips.padding(.bottom, 12)
                }
                FormDivider()
            }
            if config.type != .abstinence && config.auto == nil {
                HStack {
                    Text("Health")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Ink.ink)
                    Spacer()
                    Picker("Health", selection: Binding(
                        get: { config.health?.metric ?? "" },
                        set: { applyHealth($0) })) {
                        Text("Keine").tag("")
                        ForEach(Self.metrics, id: \.0) { metric, title in
                            Text(title).tag(metric)
                        }
                    }
                    .tint(Ink.muted)
                }
                .frame(minHeight: 56)
                FormDivider()
            }
            Button { showsZones = true } label: {
                FormRow(title: "Zeitzone") { RowValue(text: config.timezone) }
            }
            .buttonStyle(.plain)
            FormDivider()
            HStack {
                Text("Nachtragsfrist")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.ink)
                Spacer()
                Picker("Nachtragsfrist", selection: $config.backfillHours) {
                    ForEach(CohabitConfig.backfillChoices, id: \.self) { hours in
                        Text(Self.backfillTitle(hours)).tag(hours)
                    }
                }
                .tint(Ink.muted)
            }
            .frame(minHeight: 56)
            FormDivider()
            reminderRow
            if config.type == .streak && config.auto == nil {
                FormDivider()
                ToggleRow(title: "Gruppen-Streak", isOn: Binding(
                    get: { config.streak?.groupStreak ?? false },
                    set: { config.streak?.groupStreak = $0 }))
            }
            FormDivider()
            ToggleRow(title: "Mitglieder dürfen einladen", isOn: $config.membersCanInvite)
        }
    }

    private var reminderRow: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { config.reminderTime != nil },
                set: { config.reminderTime = $0 ? (config.reminderTime ?? "07:30") : nil })) {
                Text("Erinnerung")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.ink)
            }
            .tint(Ink.accent)
            if config.reminderTime != nil {
                DatePicker("", selection: reminderBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "de_DE"))
            }
        }
        .frame(minHeight: 56)
    }

    private var reminderBinding: Binding<Date> {
        Binding(
            get: {
                let parts = (config.reminderTime ?? "07:30").split(separator: ":").compactMap { Int($0) }
                var components = DateComponents()
                components.hour = parts.first ?? 7
                components.minute = parts.count > 1 ? parts[1] : 30
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                config.reminderTime = String(format: "%02d:%02d", components.hour ?? 7, components.minute ?? 30)
            })
    }

    static let metrics = [("STEPS", "Schritte"), ("RUNNING_DISTANCE", "Laufdistanz"),
                          ("WORKOUTS", "Trainings"), ("WORKOUT_MINUTES", "Trainingsminuten"),
                          ("KCAL", "kcal aus Healthy")]

    /// Eine Health-Metrik bringt ihre Einheit mit - ein Ziel „100.000
    /// Schritte" zaehlt Mengen, keine Eintraege.
    private func applyHealth(_ metric: String) {
        guard !metric.isEmpty else {
            config.health = nil
            return
        }
        config.health = .init(metric: metric)
        config.tracking = .init(mode: "VALUE", unit: Self.unit(forHealthMetric: metric))
        if config.type == .goal { config.goal?.counting = "AMOUNT" }
        if config.type == .challenge, config.challenge?.scoring == "MOST_ENTRIES" {
            config.challenge?.scoring = "HIGHEST_SUM"
        }
    }

    /// Die Einheit, die eine Health-Metrik mitbringt.
    nonisolated static func unit(forHealthMetric metric: String) -> String {
        switch metric {
        case "STEPS": "STEPS"
        case "RUNNING_DISTANCE": "KM"
        case "WORKOUT_MINUTES": "MINUTES"
        case "KCAL": "KCAL"
        default: "COUNT"
        }
    }

    nonisolated static func backfillTitle(_ hours: Int) -> String {
        switch hours {
        case 0: "keine"
        case 168: "7 Tage"
        case 336: "14 Tage"
        default: "\(hours) Stunden"
        }
    }

    // MARK: - Hilfen

    private func choiceChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Ink.onInk : Ink.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(selected ? Ink.ink : Ink.track, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("choice-\(title)")
    }

    /// Ein Kalendertag als `Date` fuer den DatePicker - in der Zone des Co-Habits.
    private func dateBinding(_ path: WritableKeyPath<CohabitConfig, CalendarDate>) -> Binding<Date> {
        let zone = TimeZone(identifier: config.timezone) ?? .current
        return Binding(
            get: { config[keyPath: path].startOfDay(in: zone) },
            set: { config[keyPath: path] = CalendarDate(date: $0, in: zone) })
    }

    /// Was einem „Weiter" im Weg steht - `nil`, wenn alles passt.
    nonisolated static func problem(_ config: CohabitConfig) -> String? {
        let name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > 40 { return "Name fehlt" }
        switch config.type {
        case .streak:
            if config.streak?.rhythm.kind == "WEEKDAYS", (config.streak?.rhythm.weekdays ?? []).isEmpty {
                return "Wochentage fehlen"
            }
        case .goal:
            guard let goal = config.goal else { return "Ziel fehlt" }
            if goal.target <= 0 { return "Zielwert fehlt" }
            if let start = goal.start, goal.deadline <= start { return "Datum liegt vor dem Start" }
        case .challenge:
            guard let challenge = config.challenge else { return "Zeitraum fehlt" }
            if challenge.end < challenge.start { return "Ende liegt vor dem Start" }
            if challenge.scoring == "FIRST_TO_TARGET", (challenge.target ?? 0) <= 0 { return "Zielwert fehlt" }
            if (challenge.stake?.count ?? 0) > 80 { return "Einsatz zu lang" }
        case .abstinence:
            break
        }
        return nil
    }
}

/// Ein Zahlenfeld fuer `Double?` - deutsch geschrieben („100.000", „5,2").
struct NumberInput: View {
    let placeholder: String
    @Binding var value: Double?
    var unit: String = "COUNT"
    var identifier: String?

    @State private var text = ""

    var body: some View {
        InputField(placeholder: placeholder, text: $text, keyboard: .decimalPad, identifier: identifier)
            .onAppear { text = value.map { ValueEntrySheet.format($0) } ?? "" }
            .onChange(of: text) { _, new in value = ValueEntrySheet.number(new, unit: unit) }
    }
}

/// Die Zeitzone - Europe/Berlin zuerst, dann alle, mit Suche.
struct TimeZonePicker: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        let filtered = query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
        return ["Europe/Berlin"].filter { filtered.contains($0) } + filtered.filter { $0 != "Europe/Berlin" }
    }

    var body: some View {
        NavigationStack {
            List(zones, id: \.self) { zone in
                Button {
                    selection = zone
                    dismiss()
                } label: {
                    HStack {
                        Text(zone).foregroundStyle(Ink.ink)
                        Spacer()
                        if zone == selection { Image(systemName: "checkmark").foregroundStyle(Ink.accent) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Suchen")
            .navigationTitle("Zeitzone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }
}
