import SwiftUI

/// Die Schritte von heute, unter dem Diagramm.
///
/// Eine Leiste und keine Tachoscheibe: der Tacho im Essen-Tab beantwortet
/// „drueber oder drunter", hier geht es um „wie weit" - und dafuer ist ein
/// Balken die naheliegendere Form. Schritte sind ausserdem ein Mindestwert;
/// eine Zielkerbe, an der man vorbeischiessen kann, waere hier sinnlos.
struct StepsCard: View {

    let steps: Int?
    let goal: Int

    private var reached: Bool { (steps ?? 0) >= goal }

    /// Gedeckelt: ueber dem Ziel bleibt die Leiste voll, statt aus dem Rahmen
    /// zu laufen. Dass es mehr war, sagt die Zahl daneben.
    private var fraction: Double {
        guard let steps, goal > 0 else { return 0 }
        return min(Double(steps) / Double(goal), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("👟")
                    .font(.title3)
                Text(zahlen)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    // Anker fuer den UI-Test. Ueber die Zahl selbst zu suchen
                    // geht nicht - die aendert sich mit jedem Schritt.
                    .accessibilityIdentifier("stepsValue")
                Spacer()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: tone.gradient,
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 10)
        }
        .padding(.vertical, 8)
        // `.combine` fasst Symbol, Zahl und Leiste zu einer Ansage zusammen -
        // sonst liest VoiceOver „Schuh" und dann zwei Zahlen ohne Zusammenhang.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritte heute")
        .accessibilityValue(steps.map { "\($0) von \(goal)" } ?? "keine Daten")
        .accessibilityIdentifier("stepsCard")
    }

    /// Ein Strich und keine Null, wenn Health nichts weiss: eine 0 waere eine
    /// Behauptung ueber einen Tag, an dem niemand gemessen hat.
    private var zahlen: String {
        let gelaufen = steps.map { Double($0).whole } ?? "–"
        return "\(gelaufen)/\(Double(goal).whole)"
    }

    /// Gruen ab dem Ziel, sonst neutral. Kein Warnton - darunter zu liegen ist
    /// kein Fehler, nur noch nicht fertig.
    private var tone: MacroTone { reached ? .good : .neutral }
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
