import SwiftUI
import UIKit

/// Zeitraeume (Baender) und einzelne Tage (Linien) in den Diagrammen -
/// ansehen, anlegen, wegwischen. Ein eigenes Blatt statt Platz im Tab: das
/// aendert sich ein paarmal im Jahr. Dieselbe Liste wie in der Weboberflaeche.
struct HighlightsSheet: View {

    let store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    if store.highlights.isEmpty {
                        Text("Noch nichts angelegt – mit + einen Zeitraum oder eine Linie anlegen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.highlights) { highlight in
                        HighlightRow(highlight: highlight)
                    }
                    .onDelete { offsets in
                        // Erst einsammeln, dann loeschen: jedes Loeschen
                        // aendert die Liste, und die Indizes gaelten nicht mehr.
                        let doomed = offsets.map { store.highlights[$0] }
                        Task {
                            for highlight in doomed { await store.removeHighlight(highlight) }
                        }
                    }
                } footer: {
                    Text("Nach links wischen entfernt einen Eintrag.")
                }
            }
            .navigationTitle("Zeiträume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Zeitraum oder Linie anlegen")
                }
            }
            .sheet(isPresented: $showingEditor) { HighlightEditorSheet(store: store) }
        }
    }
}

/// Eine Zeile: Farbe, Beschriftung, Datum.
private struct HighlightRow: View {

    let highlight: Highlight

    var body: some View {
        HStack(spacing: 12) {
            // Band als Kaestchen, Linie als Strich - so sieht man die Art,
            // ohne dass sie dabeisteht.
            Group {
                if highlight.kind == .line {
                    Capsule().frame(width: 3, height: 18)
                } else {
                    RoundedRectangle(cornerRadius: 4).frame(width: 18, height: 18)
                }
            }
            .foregroundStyle(highlight.swiftUIColor)
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.label ?? highlight.kind.title)
                Text(dates)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dates: String {
        highlight.kind == .line
            ? highlight.start.short
            : "\(highlight.start.short) – \(highlight.end.short)"
    }
}

/// Neuen Zeitraum oder neue Linie anlegen.
struct HighlightEditorSheet: View {

    let store: WeightStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: HighlightKind = .band
    @State private var start = Date()
    @State private var end = Date()
    @State private var label = ""
    @State private var colorHex = HighlightPalette.defaultHex
    @State private var customColor = HighlightPalette.presets[0].color
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(HighlightKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    DatePicker(kind == .line ? "Tag" : "Von",
                               selection: $start, displayedComponents: .date)
                    if kind == .band {
                        DatePicker("Bis", selection: $end, in: start...,
                                   displayedComponents: .date)
                    }
                    TextField("Beschriftung", text: $label)
                } footer: {
                    Text(kind == .line
                         ? "Eine Linie markiert einen einzelnen Tag."
                         : "Ein Zeitraum wird als Band hinterlegt.")
                }

                Section("Farbe") {
                    // Die Vorgaben als Kreise; ausgewaehlt ist, was der
                    // Farbwaehler darunter gerade zeigt.
                    HStack(spacing: 10) {
                        ForEach(HighlightPalette.presets) { preset in
                            Button {
                                colorHex = preset.hex
                                customColor = preset.color
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(
                                        Color.primary, lineWidth: colorHex == preset.hex ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                            .accessibilityAddTraits(colorHex == preset.hex ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    ColorPicker("Eigene Farbe", selection: $customColor, supportsOpacity: false)
                }
            }
            .onChange(of: customColor) { _, color in
                if let hex = color.hexString { colorHex = hex }
            }
            .onChange(of: start) { _, day in
                if end < day { end = day }
            }
            .navigationTitle(kind == .line ? "Linie" : "Zeitraum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = NewHighlightRequest(
            kind: kind,
            start: CalendarDate(date: start),
            end: kind == .band ? CalendarDate(date: end) : nil,
            label: trimmed.isEmpty ? nil : trimmed,
            color: colorHex)
        if await store.addHighlight(request) {
            dismiss()
        }
    }
}

// MARK: - Farben

extension Highlight {
    /// Die Farbe des Eintrags - oder das alte Urlaubsblau, wenn der Dienst
    /// etwas schickt, das keine `#rrggbb`-Farbe ist.
    var swiftUIColor: Color {
        colorValue.map { Color(hex: $0) } ?? Palette.vacation
    }
}

/// Die Farbvorgaben beim Anlegen - dieselbe Reihe wie in der Weboberflaeche
/// (`HIGHLIGHT_PRESETS` in app.js); die erste ist das Blau, das die
/// Urlaubsbaender immer hatten.
enum HighlightPalette {

    struct Preset: Identifiable, Sendable {
        let name: String
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0) }
    }

    static let presets: [Preset] = [
        Preset(name: "Blau", hex: "#7c9cfa"),
        Preset(name: "Rot", hex: "#ef5350"),
        Preset(name: "Grün", hex: "#66bb6a"),
        Preset(name: "Orange", hex: "#ffa726"),
        Preset(name: "Lila", hex: "#ba68c8"),
        Preset(name: "Gelb", hex: "#ffd54f"),
        Preset(name: "Türkis", hex: "#4dd0e1"),
        Preset(name: "Grau", hex: "#90a4ae"),
    ]

    static let defaultHex = presets[0].hex
}

extension Color {
    /// Die Farbe als `#rrggbb` - so will sie der Dienst. `nil`, wenn sie sich
    /// nicht in RGB ausdruecken laesst; bei einer Farbe aus dem Waehler kommt
    /// das nicht vor, der Typ verlangt es trotzdem.
    var hexString: String? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(format: "#%02x%02x%02x",
                      Int((red * 255).rounded()),
                      Int((green * 255).rounded()),
                      Int((blue * 255).rounded()))
    }
}
