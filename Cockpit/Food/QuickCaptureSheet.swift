import SwiftUI

/// Schnellerfassung: Freitext rein, Vorschlag raus.
///
/// Der Vorschlag wird **nicht** automatisch eingetragen. Eine geschaetzte
/// Zahl, die ungefragt im Tagebuch landet, sieht dort hinterher genauso aus
/// wie eine abgelesene.
struct QuickCaptureSheet: View {

    let store: FoodStore
    let meal: Meal?
    /// Wird gerufen, wenn ein Eintrag entstanden ist - dann kann auch das
    /// Blatt darunter zu.
    let onEntered: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isRunning = false
    @State private var message: String?
    @State private var preview: QuickCapturePreview?
    @State private var isSaving = false

    // Der Vorschlag ist ein Vorschlag: alles daran laesst sich korrigieren,
    // bevor er zum Eintrag wird.
    @State private var name = ""
    @State private var gramsText = ""
    @State private var portionText = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var edited = false

    var body: some View {
        NavigationStack {
            Form {
                if preview == nil {
                    Section {
                        TextField("z. B. ein großer Teller Spaghetti Bolognese",
                                  text: $text, axis: .vertical)
                            .lineLimit(3...6)
                            .disabled(isRunning)
                    } header: {
                        Text("Was hast du gegessen?")
                    } footer: {
                        Text("Die Auswertung läuft auf dem Server und dauert "
                             + "je nach Gericht bis zu einer Minute.")
                    }

                    if isRunning {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Wird ausgewertet …").foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    proposalSections
                }

                if let message {
                    Section {
                        Text(message).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .navigationTitle("Schnellerfassung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(preview == nil ? "Abbrechen" : "Verwerfen") {
                        if preview == nil { dismiss() } else { preview = nil }
                    }
                    .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if preview == nil {
                        Button("Auswerten") { Task { await run() } }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)
                    } else {
                        Button("Übernehmen") { Task { await confirm() } }
                            .disabled(isSaving)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var proposalSections: some View {
        Section {
            TextField("Name", text: $name)
                .onChange(of: name) { edited = true }
            if let preview, !preview.known {
                Label("Neues Gericht", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note = preview?.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Vorschlag")
        }

        Section("Nährwerte je 100 g") {
            valueRow("kcal", $kcalText, source: "kcal")
            valueRow("Eiweiß", $proteinText, source: "proteinG")
            valueRow("Kohlenhydrate", $carbsText, source: "carbsG")
            valueRow("Fett", $fatText, source: "fatG")
        }

        Section("Menge") {
            LabeledContent("Gramm") { decimalField($gramsText) }
            LabeledContent("Portion (g, optional)") { decimalField($portionText) }
        }
    }

    private func valueRow(_ label: String, _ binding: Binding<String>, source: String) -> some View {
        LabeledContent {
            decimalField(binding)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                // Woher der Wert stammt - der Agent unterscheidet
                // Nachgeschlagenes von Geschaetztem, und das gehoert
                // danebengeschrieben.
                if let origin = preview?.valueSources[source], !origin.isEmpty {
                    Text(origin).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func decimalField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110)
            .onChange(of: text.wrappedValue) { edited = true }
    }

    private func run() async {
        isRunning = true
        message = nil
        defer { isRunning = false }
        switch await store.runQuickCapture(text: text, meal: meal) {
        case .ready(let result):
            apply(result)
        case .failed(let reason):
            message = reason
        }
    }

    private func apply(_ result: QuickCapturePreview) {
        preview = result
        name = result.name
        gramsText = result.grams.whole
        portionText = result.portionG?.whole ?? ""
        kcalText = result.per100g.kcal.oneDecimal
        proteinText = result.per100g.proteinG.oneDecimal
        carbsText = result.per100g.carbsG.oneDecimal
        fatText = result.per100g.fatG.oneDecimal
        edited = false
    }

    private func confirm() async {
        guard let preview, let grams = AddEntrySheet.number(gramsText) else { return }
        isSaving = true
        defer { isSaving = false }

        // Unveraendert und schon bekannt: dann reicht die Kennung, und es
        // entsteht kein zweites Gericht mit demselben Namen.
        let ok: Bool
        if preview.known, let dishId = preview.dishId, !edited {
            ok = await store.addEntry(dishId: dishId, dish: nil, grams: grams,
                                      meal: preview.meal ?? meal)
        } else {
            let request = DishRequest(name: name.trimmingCharacters(in: .whitespaces),
                                      kcal: AddEntrySheet.number(kcalText),
                                      proteinG: AddEntrySheet.number(proteinText),
                                      carbsG: AddEntrySheet.number(carbsText),
                                      fatG: AddEntrySheet.number(fatText),
                                      portionG: AddEntrySheet.number(portionText))
            ok = await store.addEntry(dishId: nil, dish: request, grams: grams,
                                      meal: preview.meal ?? meal)
        }
        if ok {
            dismiss()
            onEntered()
        }
    }
}
