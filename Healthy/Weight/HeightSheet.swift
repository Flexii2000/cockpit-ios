import SwiftUI

/// Koerpergroesse fuer den BMI (seit 10.11.). Sie liegt je Person beim Weight
/// Tracker - vorher stand Felix' Groesse fest im Code, und Healthy bei einer
/// zweiten Person haette mit ihr gerechnet.
struct HeightSheet: View {

    let store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSaving = false

    /// Nur, was der Dienst auch annimmt - sonst kaeme die Absage erst nach dem Sichern.
    private var height: Double? {
        HeightSheet.parse(text)
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Größe (cm)") {
                    TextField("", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("heightField")
                }
            }
            .navigationTitle("Größe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(height == nil || isSaving)
                }
            }
            .onAppear {
                if let known = store.summary?.heightCm, text.isEmpty {
                    text = known.whole
                }
            }
        }
    }

    /// Zentimeter mit Komma oder Punkt, im Bereich des Dienstes (100–250).
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), UpdateHeightRequest.range.contains(value) else { return nil }
        return value
    }

    private func save() async {
        guard let height else { return }
        isSaving = true
        defer { isSaving = false }
        if await store.updateHeight(height) {
            dismiss()
        }
    }
}
