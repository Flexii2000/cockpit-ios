import SwiftUI

/// Essen - nativ seit M2.
struct FoodTab: View {

    @State private var store = FoodStore()
    @State private var addTarget: AddTarget?
    @State private var showingTargets = false
    @State private var showingDatePicker = false

    /// Traegt die Mahlzeit, aus deren Abschnitt heraus „+" getippt wurde.
    struct AddTarget: Identifiable {
        let meal: Meal?
        var id: String { meal?.rawValue ?? "any" }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error {
                    Section {
                        ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if let day = store.day {
                    Section { gauges(day) }
                    ForEach(store.mealSections) { section in
                        mealSection(section, day: day)
                    }
                    historySection(day)
                } else if store.isLoading {
                    Section { LoadingPlaceholder() }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .refreshable { await store.load() }
            .task { await store.load() }
            .sheet(item: $addTarget) { target in
                AddEntrySheet(store: store, meal: target.meal)
            }
            .sheet(isPresented: $showingTargets) { TargetsSheet(store: store) }
            .sheet(isPresented: $showingDatePicker) { datePicker }
        }
    }

    private var title: String {
        store.isToday ? "Heute" : store.date.short
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { Task { await store.step(days: -1) } } label: {
                Image(systemName: "chevron.left")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            // Vorwaerts nur bis heute: fuer morgen gibt es nichts einzutragen.
            Button { Task { await store.step(days: 1) } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(store.isToday)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Tag wählen …") { showingDatePicker = true }
                if !store.isToday {
                    Button("Heute") { Task { await store.show(.today()) } }
                }
                Divider()
                NavigationLink("Gerichte verwalten") { DishListView(store: store) }
                Button("Tagesziele …") { showingTargets = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var datePicker: some View {
        NavigationStack {
            DatePicker("Tag",
                       selection: Binding(
                        get: { store.date.startOfDay() },
                        set: { newValue in
                            let parts = Calendar(identifier: .gregorian)
                                .dateComponents([.year, .month, .day], from: newValue)
                            Task {
                                await store.show(CalendarDate(year: parts.year ?? 2026,
                                                              month: parts.month ?? 1,
                                                              day: parts.day ?? 1))
                            }
                        }),
                       displayedComponents: .date)
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Tag wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { showingDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Tachos

    private func gauges(_ day: DaySummary) -> some View {
        VStack(spacing: 16) {
            // Makros oben, kcal darunter: die drei kleinen zeigen das schon
            // Verzehrte, der grosse das, was vom Tagesziel noch uebrig ist.
            HStack(spacing: 8) {
                ForEach(Macro.allCases) { macro in
                    VStack(spacing: 4) {
                        GaugeView(
                            ratio: ratio(macro.value(day.consumed), macro.value(day.targets)),
                            tone: NutritionTone.tone(for: macro, consumed: day.consumed,
                                                     targets: day.targets),
                            main: macro.value(day.consumed).whole,
                            sub: "von \(macro.value(day.targets).whole) g",
                            lineWidth: 6,
                            mainFont: .subheadline,
                            subFont: .system(size: 9))
                        .frame(height: 84)
                        Text(macro.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 16) {
                GaugeView(
                    ratio: ratio(day.consumed.kcal, day.targets.kcal),
                    tone: NutritionTone.kcalTone(consumed: day.consumed, targets: day.targets),
                    main: abs(day.remaining.kcal).whole,
                    sub: day.remaining.kcal < 0 ? "kcal drüber" : "kcal übrig",
                    lineWidth: 8,
                    mainFont: .title2)
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verzehrt").font(.caption).foregroundStyle(.secondary)
                    Text("\(day.consumed.kcal.whole) kcal").font(.title3.weight(.semibold))
                    Text("von \(day.targets.kcal.whole) kcal")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }

    /// Der Bogen reicht bis zum 1,25-fachen des Ziels - sonst saesse die
    /// Zielmarke am Ende und man saehe nie, ob man knapp oder weit darueber ist.
    private func ratio(_ consumed: Double, _ target: Double) -> Double {
        target > 0 ? consumed / (target * 1.25) : 0
    }

    // MARK: - Mahlzeiten

    private func mealSection(_ section: MealSection, day: DaySummary) -> some View {
        Section {
            ForEach(section.entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                        Text("\(entry.grams.whole) g")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(entry.total.kcal.whole) kcal")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { section.entries[$0] }
                Task { for entry in doomed { await store.deleteEntry(entry) } }
            }

            if let meal = section.meal {
                Button {
                    addTarget = AddTarget(meal: meal)
                } label: {
                    Label("Hinzufügen", systemImage: "plus.circle")
                        .font(.callout)
                }
            }
        } header: {
            HStack {
                Text(section.label)
                Spacer()
                // Teilsumme gegen das Ziel dieser Mahlzeit - „war das
                // Fruehstueck zu gross?" laesst sich an einer Tagessumme
                // nicht beantworten.
                if let meal = section.meal, let target = day.targetsByMeal[meal], target > 0 {
                    Text("\(section.total.kcal.whole)/\(target.whole) kcal")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(section.total.kcal > target + NutritionTone.kcalTolerance
                                         ? .orange : .secondary)
                } else if !section.entries.isEmpty {
                    Text("\(section.total.kcal.whole) kcal")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Verlauf

    private func historySection(_ day: DaySummary) -> some View {
        Section("Verlauf") {
            Picker("Zeitraum", selection: Binding(
                get: { store.historyDays },
                set: { days in
                    store.historyDays = days
                    Task { await store.loadHistory() }
                })) {
                ForEach([14, 30, 90], id: \.self) { days in
                    Text("\(days) Tage").tag(days)
                }
            }
            .pickerStyle(.segmented)

            FoodChartView(history: store.history,
                          weightPoints: store.weightPoints,
                          kcalTarget: day.targets.kcal,
                          from: store.historyFrom,
                          to: store.historyTo)

            HStack(spacing: 14) {
                Label("kcal", systemImage: "minus")
                    .foregroundStyle(Palette.kcal)
                Label("über Ziel", systemImage: "circle.fill")
                    .foregroundStyle(Palette.over)
                Label("Gewicht", systemImage: "minus")
                    .foregroundStyle(Palette.avg7)
            }
            .font(.caption2)
        }
    }
}
