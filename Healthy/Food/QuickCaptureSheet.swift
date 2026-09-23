import PhotosUI
import SwiftUI

/// Schnellerfassung: Freitext oder ein Foto rein, Blatt zu.
///
/// Gewartet wird nicht mehr hier - der Auftrag laeuft im Store weiter und
/// meldet sich, wenn der Vorschlag da ist. Eine Minute auf ein Blatt zu
/// starren, das nichts tut, war der schlechteste Teil des Ablaufs.
///
/// Mit Foto ist der Text Kontext („die kleine Portion", „mit extra Kaese")
/// und darf leer bleiben - der Agent sieht sich das Bild an.
struct QuickCaptureSheet: View {

    let store: FoodStore
    let meal: Meal?
    /// Wird gerufen, wenn der Auftrag weg ist - dann kann auch das Blatt
    /// darunter zugehen.
    let onStarted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: UIImage?
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?

    private var canSubmit: Bool {
        photo != nil || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let photo {
                        HStack(alignment: .top, spacing: 12) {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Button("Entfernen", role: .destructive) { self.photo = nil }
                                .font(.callout)
                            Spacer()
                        }
                    } else {
                        if CameraPicker.isAvailable {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Foto aufnehmen", systemImage: "camera")
                            }
                            .accessibilityIdentifier("takePhoto")
                        }
                        PhotosPicker(selection: $libraryItem, matching: .images) {
                            Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
                        }
                    }
                } header: {
                    Text("Foto")
                }
                Section {
                    TextField(photo == nil ? "z. B. ein großer Teller Spaghetti Bolognese"
                                           : "optional: Kontext, z. B. die kleine Portion",
                              text: $text, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(photo == nil ? "Was hast du gegessen?" : "Dazu")
                } footer: {
                    Text("Die Auswertung läuft auf dem Server und dauert bis zu "
                         + "einer Minute. Du kannst die App derweil weiter "
                         + "benutzen – der Vorschlag meldet sich von selbst.")
                }
            }
            .navigationTitle("Schnellerfassung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Auswerten") {
                        store.startQuickCapture(text: text, meal: meal, photo: photo)
                        dismiss()
                        onStarted()
                    }
                    .disabled(!canSubmit)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in photo = image }
                    .ignoresSafeArea()
            }
            // Aus der Mediathek: das Bild kommt als Daten, erst hier wird es
            // ein UIImage - so bleibt der Picker frei von Berechtigungen.
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photo = image
                    }
                    libraryItem = nil
                }
            }
        }
    }
}

/// Der fertige Vorschlag.
///
/// Eingetragen wird er erst nach dem Bestaetigen: eine geschaetzte Zahl, die
/// ungefragt im Tagebuch landet, sieht dort hinterher genauso aus wie eine
/// abgelesene.
struct QuickCapturePreviewSheet: View {

    let store: FoodStore
    let preview: QuickCapturePreview
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var gramsText = ""
    @State private var portionText = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var edited = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onChange(of: name) { edited = true }
                    if !preview.known {
                        Label("Neues Gericht", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = preview.note, !note.isEmpty {
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
            .navigationTitle(preview.meal?.label ?? "Vorschlag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Verwerfen", role: .destructive) {
                        store.discardPreview()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { Task { await confirm() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func valueRow(_ label: String, _ binding: Binding<String>,
                          source: String) -> some View {
        LabeledContent {
            decimalField(binding)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                // Woher der Wert stammt - der Agent unterscheidet
                // Nachgeschlagenes von Geschaetztem, und das gehoert
                // danebengeschrieben.
                if let origin = preview.valueSources[source], !origin.isEmpty {
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

    private func fill() {
        guard name.isEmpty else { return }
        name = preview.name
        gramsText = preview.grams.whole
        portionText = preview.portionG?.whole ?? ""
        kcalText = preview.per100g.kcal.oneDecimal
        proteinText = preview.per100g.proteinG.oneDecimal
        carbsText = preview.per100g.carbsG.oneDecimal
        fatText = preview.per100g.fatG.oneDecimal
        edited = false
    }

    private func confirm() async {
        guard let grams = AddEntrySheet.number(gramsText) else { return }
        isSaving = true
        defer { isSaving = false }

        // Unveraendert und schon bekannt: dann reicht die Kennung, und es
        // entsteht kein zweites Gericht mit demselben Namen.
        let ok: Bool
        if preview.known, let dishId = preview.dishId, !edited {
            ok = await store.addEntry(dishId: dishId, dish: nil, grams: grams,
                                      meal: preview.meal)
        } else {
            let request = DishRequest(name: name.trimmingCharacters(in: .whitespaces),
                                      kcal: AddEntrySheet.number(kcalText),
                                      proteinG: AddEntrySheet.number(proteinText),
                                      carbsG: AddEntrySheet.number(carbsText),
                                      fatG: AddEntrySheet.number(fatText),
                                      portionG: AddEntrySheet.number(portionText))
            ok = await store.addEntry(dishId: nil, dish: request, grams: grams,
                                      meal: preview.meal)
        }
        if ok {
            store.discardPreview()
            dismiss()
        }
    }
}
