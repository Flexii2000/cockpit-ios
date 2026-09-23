import SwiftUI

/// Essen - nativ seit M2.
struct FoodTab: View {

    @State private var store = FoodStore()
    @State private var addTarget: AddTarget?
    @State private var editing: FoodEntry?
    @State private var showingTargets = false
    @State private var showingDatePicker = false
    /// Wie weit die Karte gerade zur Seite gezogen ist - negativ nach links
    /// (der naechste Tag kommt von rechts), positiv nach rechts.
    @State private var drag: CGFloat = 0
    /// Ob die laufende Geste als waagerecht (Karte) oder senkrecht (Liste
    /// scrollt) erkannt wurde; nil, solange sie noch nicht entschieden ist.
    @State private var horizontal: Bool?
    @State private var pageWidth: CGFloat = 390

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
            // Gestern, heute, morgen als Karten: die Geste zieht die eine hinaus
            // und die naechste herein, beide sichtbar. Kein Pager-Scrollfeld -
            // das schluckte jeden Wisch nach links, auch den zum Loeschen einer
            // Eintragszeile (Felix, 2026-09-23). Stattdessen liegt die Geste nur
            // auf Tacho-Block, Mahlzeiten-Ueberschriften und „Hinzufuegen"-Zeilen,
            // und die Nachbarkarte wird erst gezeichnet, wenn gezogen wird.
            GeometryReader { geo in
                ZStack {
                    dayList(store.date)
                        .offset(x: drag)
                    if drag < 0 {
                        dayList(store.date.adding(days: 1))
                            .offset(x: geo.size.width + drag)
                    } else if drag > 0 {
                        dayList(store.date.adding(days: -1))
                            .offset(x: -geo.size.width + drag)
                    }
                }
                .clipped()
                .onAppear { pageWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, width in pageWidth = width }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .food) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $editing) { entry in
                EditEntrySheet(store: store, entry: entry)
            }
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

    // MARK: - Die Karten-Geste

    /// Zieht die Karte mit dem Finger. `simultaneousGesture`, damit die Liste
    /// darunter weiter senkrecht scrollt; die erste deutliche Bewegung
    /// entscheidet, ob es eine Karte oder ein Scrollen wird. Losgelassen
    /// entscheidet die vorausberechnete Endlage: ueber ein Drittel der
    /// Breite (oder ein Schwung dorthin) blaettert, sonst federt die Karte
    /// zurueck.
    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                if horizontal == nil {
                    horizontal = abs(value.translation.width) > abs(value.translation.height)
                }
                guard horizontal == true else { return }
                drag = max(-pageWidth, min(pageWidth, value.translation.width))
            }
            .onEnded { value in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                let predicted = value.predictedEndTranslation.width
                if predicted < -pageWidth / 3 {
                    turn(1)
                } else if predicted > pageWidth / 3 {
                    turn(-1)
                } else {
                    withAnimation(.spring(duration: 0.3)) { drag = 0 }
                }
            }
    }

    /// Blaettert um einen Tag: die Karte gleitet zu Ende, dann wird der neue
    /// Tag zum Haupttag und die Verschiebung ohne Animation zurueckgesetzt -
    /// die Nachbarkarte stand schon genau dort, wo die neue Hauptkarte
    /// erscheint, das Auge sieht keinen Sprung.
    private func turn(_ days: Int) {
        let target = store.date.adding(days: days)
        withAnimation(.easeOut(duration: 0.28)) {
            drag = days > 0 ? -pageWidth : pageWidth
        } completion: {
            Task { @MainActor in
                await store.show(target)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { drag = 0 }
            }
        }
    }

    /// Eine Karte: die Liste eines Tages. Die Meldungen oben (Fehler,
    /// laufende Auswertung, Scanner) stehen auf jeder Karte - sie gehoeren
    /// zum Tab, nicht zum Tag.
    private func dayList(_ date: CalendarDate) -> some View {
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

            if let day = store.summary(for: date) {
                Section {
                    gauges(day)
                        // Die ganze Zeile nimmt die Karten-Geste an, nicht nur die Bogen.
                        .contentShape(Rectangle())
                        .simultaneousGesture(cardDrag)
                }
                ForEach(FoodStore.mealSections(of: day)) { section in
                    mealSection(section, day: day)
                }
                historySection(day)
            } else {
                Section { LoadingPlaceholder() }
            }
        }
        .refreshable { await store.load() }
        .frame(width: pageWidth)
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

    /// Die Pfeile schieben die Karte, als haette man gezogen.
    private func step(_ days: Int) {
        guard drag == 0 else { return }
        turn(days)
    }

    /// Ein beliebiger Tag („Tag waehlen", „Heute"): ohne Karte daneben, also
    /// laedt der Store, und die Liste zeigt ihn.
    private func show(_ date: CalendarDate) {
        Task { await store.show(date) }
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
                .simultaneousGesture(cardDrag)
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
            .simultaneousGesture(cardDrag)
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
