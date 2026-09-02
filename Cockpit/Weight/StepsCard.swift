import SwiftUI

/// Die Schritte von heute, unter dem Diagramm.
///
/// Derselbe Tacho wie im Essen-Tab: im Bogen steht, was noch fehlt, daneben
/// die Tageszahl. Ein eigenes Kachel-Rechteck waere hier die fuenfte Kachel in
/// einer anderen Groesse gewesen - der Tacho ist das Bauteil fuer „ein Wert
/// gegen ein Tagesziel", samt Zielkerbe.
struct StepsCard: View {

    let steps: Int?
    let goal: Int
    let onEditGoal: () -> Void

    private var remaining: Int? { steps.map { max(goal - $0, 0) } }
    private var reached: Bool { (steps ?? 0) >= goal }

    var body: some View {
        HStack(spacing: 16) {
            GaugeView(
                ratio: steps.map { Double($0) / (Double(goal) * GaugeView.headroom) } ?? 0,
                // Schritte sind ein Mindestwert: mehr ist besser. Gruen ab dem
                // Ziel, sonst neutral - kein Warnton, denn darunter zu liegen
                // ist kein Fehler.
                tone: reached ? .good : .neutral,
                main: mainText,
                sub: subText,
                lineWidth: 8,
                mainFont: .title2)
            .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 2) {
                Text("Schritte heute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Ein Strich und keine Null: Health unterscheidet „nichts
                // gemessen" nicht von „null Schritte" - eine 0 waere eine
                // Behauptung ueber einen Tag, ueber den niemand etwas weiss.
                Text(steps.map { Double($0).whole } ?? "–")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Button {
                    onEditGoal()
                } label: {
                    Text("Ziel: \(Double(goal).whole)")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        // `.contain` macht die Karte als ein Element abfragbar. Nur eine
        // Kennung an den HStack zu haengen reicht nicht - dann taucht sie in
        // der Elementliste gar nicht auf, und ein Test sucht vergeblich.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stepsCard")
    }

    private var mainText: String {
        guard let remaining else { return "–" }
        return reached ? "geschafft" : Double(remaining).whole
    }

    private var subText: String {
        guard steps != nil else { return "keine Daten" }
        return reached ? "" : "Schritte fehlen"
    }
}

/// Tagesziel aendern.
struct StepsGoalSheet: View {

    let store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSaving = false

    private var goal: Int? { Int(text.filter(\.isNumber)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Schritte pro Tag") {
                        TextField("10000", text: $text)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                } footer: {
                    Text("Gilt ab sofort. Die bereits erfassten Tage bleiben, "
                         + "wie sie sind – das Ziel färbt nur die Anzeige.")
                }
            }
            .navigationTitle("Schrittziel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            guard let goal else { return }
                            isSaving = true
                            defer { isSaving = false }
                            if await store.updateStepsGoal(goal) { dismiss() }
                        }
                    }
                    .disabled(goal == nil || goal == 0 || isSaving)
                }
            }
            .onAppear { if text.isEmpty { text = String(store.stepsGoal) } }
        }
    }
}
