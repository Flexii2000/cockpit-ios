import SwiftUI

/// Neuen Messwert eintragen.
struct WeightEntrySheet: View {

    let store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var text = ""
    @State private var isSaving = false

    private var weight: Double? {
        // Auf dem Zahlenblock kommt je nach Tastatur ein Komma - beides gilt.
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)

                LabeledContent("Gewicht") {
                    TextField("kg", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Messwert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(weight == nil || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let weight else { return }
        isSaving = true
        defer { isSaving = false }
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = CalendarDate(year: parts.year ?? 1970,
                               month: parts.month ?? 1,
                               day: parts.day ?? 1)
        if await store.add(date: day, weightKg: weight) {
            dismiss()
        }
    }
}

/// Zielgewicht aendern. Eigenes Blatt und nicht in der Hauptansicht: das
/// passiert selten, und ein Fehlgriff formt die komplette Zielkurve um.
struct WeightTargetSheet: View {

    let store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSaving = false

    private var weight: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Zielgewicht") {
                        TextField("kg", text: $text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Ändert die gesamte Zielkurve und damit auch den Zieltag.")
                }
            }
            .navigationTitle("Ziel anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(weight == nil || isSaving)
                }
            }
            .onAppear {
                if let goal = store.summary?.goalWeight, text.isEmpty {
                    text = String(format: "%.1f", goal)
                }
            }
        }
    }

    private func save() async {
        guard let weight else { return }
        isSaving = true
        defer { isSaving = false }
        if await store.updateTarget(weight) {
            dismiss()
        }
    }
}
