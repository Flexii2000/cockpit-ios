import SwiftUI

/// Die Notenuebersicht - dieselben Zahlen wie `fherrmann.com/grades`.
///
/// Gerechnet wird weiterhin auf dem Server: die Regel aus PO-I23 § 8 Abs. 2
/// (ECTS-gewichtet, Thesis dreifach) steht an genau einer Stelle. Diese
/// Ansicht zeigt sie nur.
///
/// Anders als im Web steht die Abschlussnote **oben**: im Browser ist sie die
/// Summenzeile unter der Tabelle, auf dem Handy waere sie damit einen
/// Bildschirm tief. Es ist die Zahl, wegen der man den Tab aufmacht.
struct GradesTab: View {

    @Environment(Access.self) private var access
    let lock: BiometricLock

    @State private var store = GradesStore()

    var body: some View {
        NavigationStack {
            Group {
                if lock.isUnlocked {
                    content
                } else {
                    LockScreen(title: "Noten sind gesperrt",
                               failure: lock.lastFailure) {
                        await unlockAndLoad()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .grades) }
            .navigationTitle("Noten")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
            }
        }
        // Beim Wechsel auf den Tab gleich fragen - ein zusaetzlicher Tipp auf
        // „Entsperren" waere ein Klick, der nichts entscheidet.
        .task { await unlockAndLoad() }
    }

    private func unlockAndLoad() async {
        await lock.unlock()
        guard lock.isUnlocked else { return }
        // Sicherstellen, dass der Geraete-Token als Cookie steht. Beim Start
        // mit diesem Tab laeuft diese Aufgabe sonst schneller als die des
        // Fensters, und die erste Anfrage ginge ohne Cookie raus - der Dienst
        // antwortet darauf mit 404, und die App meldete faelschlich einen
        // fehlenden Zugang.
        await access.applyCookies()
        await store.load(access: access, lock: lock)
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if let overview = store.overview {
            List {
                summary(overview)
                modules(overview)
                progress(overview)
                unassigned(overview)
                howItIsCalculated(overview)
            }
            .refreshable { await store.load(access: access, lock: lock) }
            .overlay(alignment: .top) { banner }
        } else if store.isLoading {
            LoadingPlaceholder()
        } else {
            VStack(spacing: 16) {
                banner
                Button("Erneut versuchen") {
                    Task { await store.load(access: access, lock: lock) }
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let message = store.errorMessage {
            ErrorBanner(message: message, isAccessProblem: store.needsSetup)
                .padding(.horizontal)
                .padding(.top, 8)
        }
    }

    // MARK: - Abschlussnote

    private func summary(_ overview: GradesOverview) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Abschlussnote")
                    .font(.headline)
                Spacer()
                Text(GradeFormat.text(overview.scenarios.assumed ?? overview.scenarios.current))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // Anker fuer den UI-Test: die Zahl selbst aendert sich mit
                    // jeder Note.
                    .accessibilityIdentifier("finalGrade")
                    .foregroundStyle(overview.scenarios.assumed != nil ? Color.accentColor : .primary)
            }
            .padding(.vertical, 4)

            if overview.scenarios.assumed != nil {
                HStack {
                    Text("mit \(store.assumptions.count) Annahme\(store.assumptions.count == 1 ? "" : "n")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Verwerfen") {
                        Task { await store.clearAssumptions() }
                    }
                    .font(.footnote)
                }
            }

            scenarioRow("best case", overview.scenarios.best, tint: .green)
            scenarioRow("average case", overview.scenarios.average, tint: .secondary)
            scenarioRow("worst case", overview.scenarios.worst, tint: .secondary)
        } footer: {
            if let asOf = overview.asOf {
                Text("Stand \(GradeFormat.stamp(asOf))")
            }
        }
    }

    private func scenarioRow(_ title: String, _ value: Double?,
                             tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(tint == .green ? tint : .secondary)
            Spacer()
            Text(GradeFormat.text(value))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(tint == .green ? tint : .primary)
        }
    }

    // MARK: - Module

    private func modules(_ overview: GradesOverview) -> some View {
        Section("Module") {
            ForEach(overview.modules.filter(\.graded)) { module in
                moduleRow(module, possible: overview.possibleGrades)
            }
        }
    }

    private func moduleRow(_ module: GradeModule, possible: [Double]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(.subheadline)
                    .foregroundStyle(module.grade == nil ? .secondary : .primary)
                if module.isMapped, let checkerName = module.checkerName {
                    // Die drei geratenen Zuordnungen (siehe CLAUDE.md des
                    // Dienstes): sichtbar machen, unter welchem Namen die Note
                    // wirklich steht - sonst sieht eine Vermutung aus wie eine
                    // Tatsache.
                    Text("↔ \(checkerName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            if let grade = module.grade {
                Text(GradeFormat.short(grade))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(grade <= 1.3 ? .green : .primary)
            } else {
                assumptionPicker(for: module, possible: possible)
            }
        }
    }

    private func assumptionPicker(for module: GradeModule,
                                  possible: [Double]) -> some View {
        Picker("Angenommene Note", selection: assumption(for: module.name)) {
            Text("offen").tag(Double?.none)
            ForEach(possible, id: \.self) { grade in
                Text(GradeFormat.short(grade)).tag(Double?.some(grade))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.subheadline)
        // Anker fuer den UI-Test. Ueber die Beschriftung zu suchen taugt
        // nicht: `labelsHidden` blendet sie nur aus, fuer die Bedienhilfen
        // heisst der Knopf weiterhin „Angenommene Note, offen".
        .accessibilityIdentifier("assumptionPicker")
    }

    /// Eine Annahme setzen heisst: neu rechnen lassen. Deshalb keine reine
    /// Zustandsvariable, sondern ein Umweg ueber den Store.
    private func assumption(for name: String) -> Binding<Double?> {
        Binding(get: { store.assumptions[name] },
                set: { value in Task { await store.setAssumption(value, for: name) } })
    }

    // MARK: - Fortschritt

    private func progress(_ overview: GradesOverview) -> some View {
        Section("Fortschritt") {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * fraction(overview))
                    }
                }
                .frame(height: 8)

                Text("\(overview.done) von \(overview.done + overview.open) Modulen bestanden · "
                     + "\(overview.ectsDone) von \(overview.ectsPlanTotal) ECTS")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func fraction(_ overview: GradesOverview) -> Double {
        let total = overview.done + overview.open
        guard total > 0 else { return 0 }
        return Double(overview.done) / Double(total)
    }

    // MARK: - Nicht zugeordnet

    @ViewBuilder
    private func unassigned(_ overview: GradesOverview) -> some View {
        if !overview.unassigned.isEmpty {
            Section {
                ForEach(overview.unassigned) { entry in
                    HStack {
                        Text(entry.subject).font(.subheadline)
                        Spacer()
                        Text(entry.grade)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            } header: {
                Text("Nicht zugeordnet")
            } footer: {
                Text("Diese Noten stehen im Notenchecker, aber in keinem Modul "
                     + "des Studienplans. Sie zählen in keiner Rechnung mit.")
            }
        }
    }

    // MARK: - Wie gerechnet wird

    private func howItIsCalculated(_ overview: GradesOverview) -> some View {
        Section("Wie gerechnet wird") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(overview.rule.name): \(overview.rule.text)")
                if let simple = overview.simpleAverage {
                    Text("Der einfache Durchschnitt aller Noten läge bei "
                         + "\(GradeFormat.text(simple)) – das zeigt der Notenchecker. "
                         + "Er gewichtet jedes Modul gleich und ist nicht die Abschlussnote.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
        }
    }
}

/// Der Bildschirm vor einem gesperrten Tab.
struct LockScreen: View {

    let title: String
    let failure: String?
    let unlock: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Entsperren") {
                Task { await unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
