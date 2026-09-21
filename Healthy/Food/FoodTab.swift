import SwiftUI

/// Essen - nativ seit M2.
struct FoodTab: View {

    @State private var store = FoodStore()
    @State private var addTarget: AddTarget?
    @State private var editing: FoodEntry?
    @State private var showingTargets = false
    @State private var showingDatePicker = false
    /// Von welcher Seite der naechste Tag hereinkommt. `nil`, solange noch
    /// nicht geblaettert wurde - der erste Aufbau soll nicht rutschen.
    @State private var slideEdge: Edge?

    @State private var showingScanner = false
    /// Was der Scanner geliefert hat. Nachgeschlagen wird erst, wenn sein
    /// Blatt zu ist - ein zweites Blatt kann vorher nicht aufgehen.
    @State private var scannedCode: String?
    @State private var scanResult: ScanResult?
    @State private var lookingUp: String?
    @State private var scanError: String?
    private let openFoodFacts = OpenFoodFactsAPI()

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

                if let running = store.running {
                    Section { runningRow(running) }
                }

                if let message = store.captureError {
                    Section {
                        ErrorBanner(message: message, isAccessProblem: false)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .onTapGesture { store.clearCaptureError() }
                    }
                }

                if let code = lookingUp {
                    Section { lookupRow(code) }
                }

                if let message = scanError {
                    Section {
                        ErrorBanner(message: message, isAccessProblem: false)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .onTapGesture { scanError = nil }
                    }
                }

                if let day = store.day {
                    Section {
                        // Beim Blaettern gleitet nur der Tacho-Block zur Seite.
                        // Ein `.id` auf der ganzen Liste baute sie neu auf -
                        // Scrollposition weg, kurzes Flackern -, und die
                        // Mahlzeiten darunter aendern sich ohnehin zeilenweise.
                        // Der ZStack ist die stabile Zeile, in der alter und
                        // neuer Block aneinander vorbeiziehen.
                        ZStack {
                            gauges(day)
                                .id(day.date)
                                .transition(dayTransition)
                        }
                        .clipped()
                        .animation(slideEdge == nil ? nil : .easeInOut(duration: 0.25),
                                   value: day.date)
                        .daySwipe(step)
                    }
                    ForEach(store.mealSections) { section in
                        mealSection(section, day: day)
                    }
                    historySection(day)
                } else if store.isLoading {
                    Section { LoadingPlaceholder() }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .food) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $editing) { entry in
                EditEntrySheet(store: store, entry: entry)
            }
            .refreshable { await store.load() }
            // Ist der Postausgang leer geworden, kennt der Server Eintraege,
            // die der Tag hier noch nicht zeigt.
            .onChange(of: OfflineStatus.shared.pending) { before, after in
                if before > 0, after == 0 { Task { await store.load() } }
            }
            .task {
                await store.load()
                #if DEBUG
                // COCKPIT_SCAN: den Scanner gleich aufmachen - einen Knopf
                // kann simctl nicht druecken. Nach dem Laden, damit die
                // Merkliste fuer den Abgleich schon da ist.
                if BarcodeScannerSheet.debugCode != nil { showingScanner = true }
                #endif
                // Ein Auftrag, der beim letzten Beenden noch lief, rechnet auf
                // dem Server weiter - hier wird er wieder aufgenommen.
                await store.resumeQuickCaptureIfNeeded()
            }
            .sheet(item: $addTarget) { target in
                AddEntrySheet(store: store, meal: target.meal)
            }
            .sheet(isPresented: $showingTargets) { TargetsSheet(store: store) }
            .sheet(isPresented: Binding(
                get: { store.pendingPreview != nil },
                set: { if !$0 { store.discardPreview() } })) {
                if let preview = store.pendingPreview {
                    QuickCapturePreviewSheet(store: store, preview: preview)
                }
            }
            .sheet(isPresented: $showingDatePicker) { datePicker }
            .sheet(isPresented: $showingScanner, onDismiss: lookUpScannedCode) {
                BarcodeScannerSheet { code in scannedCode = code }
            }
            .sheet(item: $scanResult) { result in
                AddEntrySheet(store: store, meal: nil, scan: result)
            }
        }
    }

    private var title: String {
        // Beim Planen springt man zwischen benachbarten Tagen hin und her -
        // "Morgen" ist dabei schneller zu erfassen als ein Datum.
        switch store.date.daysFromToday() {
        case 0:  "Heute"
        case 1:  "Morgen"
        case -1: "Gestern"
        default: store.date.short
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            // Auch in die Zukunft: Mahlzeiten lassen sich vorplanen, und das
            // Backend nimmt Eintraege mit beliebigem Datum an - `today()`
            // steht dort nur als Vorgabe, wenn keins mitkommt.
            Button { step(1) } label: {
                Image(systemName: "chevron.right")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingScanner = true } label: {
                Image(systemName: "barcode.viewfinder")
            }
            .accessibilityLabel("Scannen")
            .accessibilityIdentifier("scanButton")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Tag wählen …") { showingDatePicker = true }
                if !store.isToday {
                    Button("Heute") { show(.today()) }
                }
                Divider()
                NavigationLink("Gerichte verwalten") { DishListView(store: store) }
                Button("Tagesziele …") { showingTargets = true }
                Divider()
                Button("Zugang …") { SetupPresenter.shared.isPresented = true }
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
                            show(CalendarDate(year: parts.year ?? 2026,
                                              month: parts.month ?? 1,
                                              day: parts.day ?? 1))
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

    // MARK: - Blaettern

    /// Pfeile und Wischen laufen hier zusammen: erst die Richtung merken,
    /// dann laden - der Uebergang liest sie, sobald der neue Tag da ist.
    private func step(_ days: Int) {
        slideEdge = days > 0 ? .trailing : .leading
        Task { await store.step(days: days) }
    }

    private func show(_ date: CalendarDate) {
        if date != store.date {
            slideEdge = date > store.date ? .trailing : .leading
        }
        Task { await store.show(date) }
    }

    /// Der neue Tag kommt von der Seite, in die gewischt wurde; der alte geht
    /// zur anderen hinaus. Ohne Richtung (erster Aufbau) gibt es keinen
    /// Uebergang.
    private var dayTransition: AnyTransition {
        guard let slideEdge else { return .identity }
        let opposite: Edge = slideEdge == .trailing ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: slideEdge).combined(with: .opacity),
                           removal: .move(edge: opposite).combined(with: .opacity))
    }

    // MARK: - Scanner

    /// Laeuft, wenn das Scanner-Blatt zu ist - erst dann darf das naechste
    /// Blatt aufgehen. Ohne Code (abgebrochen) passiert nichts.
    private func lookUpScannedCode() {
        guard let code = scannedCode else { return }
        scannedCode = nil
        scanError = nil
        lookingUp = code
        Task {
            do {
                let product = try await openFoodFacts.product(code: code)
                scanResult = ScanResult(code: code, product: product)
            } catch {
                scanError = error.localizedDescription
            }
            lookingUp = nil
        }
    }

    private func lookupRow(_ code: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Suche \(code) …").font(.callout)
            Spacer()
        }
    }

    /// Zeigt, dass im Hintergrund noch etwas laeuft. Ohne das waere nach dem
    /// Abschicken nichts mehr zu sehen und man wuesste nicht, ob es angekommen
    /// ist.
    private func runningRow(_ running: FoodStore.RunningCapture) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Wird ausgewertet …").font(.callout)
                if !running.text.isEmpty {
                    Text(running.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
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
        // Die ganze Zeile nimmt den Wisch an, nicht nur die Bogen.
        .contentShape(Rectangle())
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
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                // Antippen berichtigt: Menge, Mahlzeit, Tag. Das Gericht
                // bleibt - wer etwas anderes gegessen hat, loescht und traegt
                // neu ein.
                .onTapGesture { editing = entry }
                // Stabiler Griff fuer den UI-Test. Ueber die Beschriftung zu
                // suchen bricht, sobald ein anderes Gericht oben steht.
                .accessibilityIdentifier("foodEntry")
                // Eigene Wischaktion statt `onDelete`: die zeigt "Löschen"
                // ausgeschrieben. Die Mülltonne sagt dasselbe und braucht
                // weniger Weg - der Titel bleibt aber am Label stehen, damit
                // VoiceOver etwas vorzulesen hat.
                // Kein Tageswechsel auf diesen Zeilen: nach links wischen
                // heisst hier schon loeschen.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await store.deleteEntry(entry) }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
            }

            if let meal = section.meal {
                Button {
                    addTarget = AddTarget(meal: meal)
                } label: {
                    Label("Hinzufügen", systemImage: "plus.circle")
                        .font(.callout)
                }
                .daySwipe(step)
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
            .contentShape(Rectangle())
            .daySwipe(step)
        }
    }

    private func toggleWeight(_ series: WeightSeries) {
        if store.weightOverlay.contains(series) {
            store.weightOverlay.remove(series)
        } else {
            store.weightOverlay.insert(series)
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
                          averages: store.historyAverage,
                          weightPoints: store.weightPoints,
                          kcalTarget: day.targets.kcal,
                          showAverage: store.showKcalAverage,
                          showDaily: store.showKcalDaily,
                          from: store.historyFrom,
                          to: store.historyTo,
                          weightOverlay: store.weightOverlay)

            VStack(alignment: .leading, spacing: 8) {
                // Vier Umschalter passen nicht in eine iPhone-Breite - seitlich scrollbar.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SeriesChip(title: "kcal ⌀", color: Palette.kcal,
                                   isOn: store.showKcalAverage) {
                            store.showKcalAverage.toggle()
                        }
                        SeriesChip(title: "kcal Tag", color: Palette.kcal.opacity(0.55),
                                   isOn: store.showKcalDaily) {
                            store.showKcalDaily.toggle()
                        }
                        SeriesChip(title: "Gewicht ⌀", color: Palette.avg7,
                                   isOn: store.weightOverlay.contains(.avg7)) {
                            toggleWeight(.avg7)
                        }
                        SeriesChip(title: "Gewicht täglich", color: Palette.measured,
                                   isOn: store.weightOverlay.contains(.measured)) {
                            toggleWeight(.measured)
                        }
                    }
                }
                Text("Gelb: kcal im 7-Tage-Mittel, blass der Tageswert; rote Punkte mehr als 100 kcal über dem Ziel.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
