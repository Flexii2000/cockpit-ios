import SwiftUI

/// Evaluation - ein paar persoenliche Fragen je Tag, 1 bis 10, und ihr Verlauf.
///
/// Nur in Healthy fuer iOS, nur auf diesem iPhone, hinter Face ID mit fuenf
/// Minuten Frist (siehe `EvaluationLock`). Die Fragen legt man hier fest; im
/// Repo stehen sie nicht.
struct EvaluationTab: View {

    let lock: EvaluationLock

    @State private var store = EvaluationStore()
    @State private var day = CalendarDate.today()
    @State private var showingQuestions = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if lock.isUnlocked {
                    content
                } else {
                    LockScreen(title: "Evaluation ist gesperrt", failure: lock.biometric.lastFailure) {
                        await lock.biometric.unlock()
                    }
                }
            }
            .navigationTitle("Evaluation")
            .toolbar {
                if lock.isUnlocked, store.isLoaded {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingQuestions = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Fragen")
                    }
                }
            }
            .sheet(isPresented: $showingQuestions) {
                EvaluationQuestionsSheet(questions: store.data.questions) { store.replaceQuestions($0) }
            }
        }
        // Sichtschutz fuer den App-Umschalter: die Sperre bleibt fuenf Minuten
        // offen, die Vorschau, die iOS beim Verlassen macht, soll trotzdem
        // nichts zeigen.
        .overlay {
            if scenePhase != .active, lock.isUnlocked { EvaluationPrivacyCover() }
        }
        .onChange(of: lock.isUnlocked, initial: true) { _, unlocked in
            if unlocked {
                store.load()
                day = .today()
            } else {
                store.unload()
                showingQuestions = false
            }
        }
    }

    // MARK: - Inhalt

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = store.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if store.isLoaded {
                    if store.data.questions.isEmpty {
                        emptyState
                    } else {
                        answers
                        history
                    }
                }
            }
            .padding(16)
            // Platz fuer die schwebende Tab-Leiste, wie im Gewicht-Tab.
            .padding(.bottom, 60)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Button("Fragen festlegen") { showingQuestions = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Antworten

    private var answers: some View {
        let today = CalendarDate.today()
        let editable = EvaluationDays.editable(today: today)
        // Ueber Mitternacht offen gelassen: dann ist „gestern“ von vorhin
        // vorgestern und nicht mehr zu setzen.
        let selected = editable.contains(day) ? day : today
        return VStack(alignment: .leading, spacing: 16) {
            Picker("Tag", selection: Binding(get: { selected }, set: { day = $0 })) {
                Text("Heute").tag(editable[0])
                Text("Gestern").tag(editable[1])
            }
            .pickerStyle(.segmented)

            ForEach(Array(store.data.questions.enumerated()), id: \.element.id) { index, question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text)
                        .font(.subheadline.weight(.medium))
                    EvaluationScaleRow(value: store.value(of: question.id, on: selected),
                                       color: EvaluationPalette.color(at: index)) { value in
                        store.toggle(value, for: question.id, on: selected, today: today)
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Verlauf

    private var history: some View {
        @Bindable var store = store
        let to = CalendarDate.today()
        let from = EvaluationChartData.start(of: store.range, today: to)
        let questions = Array(store.data.questions.enumerated())
        return VStack(alignment: .leading, spacing: 16) {
            // Fuenf Zeitraeume: gleich breit wuerde „180 Tage“ abgeschnitten,
            // wie im Gewicht-Tab (ContentWidthSegments).
            ContentWidthSegments(options: EvaluationRange.allCases, title: \.title,
                                 selection: $store.range)
                .accessibilityLabel("Zeitraum")

            EvaluationChartView(
                series: questions
                    .filter { !store.hidden.contains($0.element.id) }
                    .map { index, question in
                        EvaluationChartView.Series(
                            id: question.id,
                            color: EvaluationPalette.color(at: index),
                            daily: EvaluationChartData.daily(store.data, question: question.id, from: from, to: to),
                            mean: EvaluationChartData.trailingMean(store.data, question: question.id,
                                                                   from: from, to: to))
                    },
                from: from, to: to)

            // Zugleich die Legende. Untereinander statt als Chips: Fragen sind
            // ganze Saetze und passten nicht nebeneinander.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(questions, id: \.element.id) { index, question in
                    legendRow(question, color: EvaluationPalette.color(at: index))
                }
            }

            let weeks = EvaluationChartData.weeks(from: from, to: to)
            ForEach(questions, id: \.element.id) { index, question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    EvaluationHeatmap(weeks: weeks,
                                      values: values(of: question.id, from: from, to: to),
                                      color: EvaluationPalette.color(at: index))
                }
            }

            // Erst ab zwei Fragen gibt es ein Paar.
            if questions.count >= 2 {
                EvaluationCorrelationsView(
                    results: EvaluationStatistics.results(store.data, from: from, to: to),
                    question: { id in store.data.questions.first { $0.id == id } })
                    .padding(.top, 8)
            }
        }
    }

    private func legendRow(_ question: EvaluationQuestion, color: Color) -> some View {
        let isOn = !store.hidden.contains(question.id)
        return Button {
            if isOn { store.hidden.insert(question.id) } else { store.hidden.remove(question.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(color)
                Text(question.text)
                    .font(.caption)
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func values(of question: UUID, from: CalendarDate, to: CalendarDate) -> [CalendarDate: Int] {
        Dictionary(uniqueKeysWithValues: EvaluationChartData
            .daily(store.data, question: question, from: from, to: to)
            .map { ($0.date, Int($0.value)) })
    }
}

/// Farben je Frage, in der Reihenfolge der Fragen - dieselben Toene wie in den
/// anderen Diagrammen, damit nichts neu gelernt werden muss.
enum EvaluationPalette {
    static let colors: [Color] = [Palette.avg7, Palette.measured, Palette.avg30,
                                  Palette.avg14, Palette.target, Palette.kcal]

    static func color(at index: Int) -> Color { colors[index % colors.count] }
}

/// Zehn Knoepfe von 1 bis 10. Der gesetzte noch einmal nimmt die Antwort zurueck.
struct EvaluationScaleRow: View {

    let value: Int?
    let color: Color
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EvaluationScale.values, id: \.self) { number in
                let isSelected = value == number
                Button {
                    select(number)
                } label: {
                    Text("\(number)")
                        .font(.subheadline.weight(isSelected ? .bold : .regular))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? color : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                        // Hintergrundfarbe als Schrift: weiss auf den dunklen
                        // Toenen des hellen Modus, schwarz auf den hellen des dunklen.
                        .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct EvaluationPrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}
