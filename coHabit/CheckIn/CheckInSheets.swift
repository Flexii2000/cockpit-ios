import SwiftUI
import UIKit

/// Das Beweisfoto-Blatt (Entwurf S. 15): Kamera-Vorschau mit Ausloeser,
/// Galerie, Kamerawechsel, bis zu vier Fotos (Vertrag §2.3a); Caption optional; der Hinweis, wer das Foto sieht
/// (Vertrag §5.1); „Posten & abhaken".
struct PhotoCheckInSheet: View {
    let target: CheckInTarget

    @State private var photos: [ProofPhoto] = []
    @State private var caption = ""
    @State private var value = ""
    @State private var otherDay = false
    @State private var day = Date()
    @State private var submitting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "\(target.name) abhaken",
                            subtitle: target.photoRequired ? "Beweisfoto erforderlich" : nil) { dismiss() }
                ProofPhotoPicker(photos: $photos, color: target.color)
                if target.valueUnit != nil {
                    FieldLabel(text: ValueEntrySheet.unitTitle(target.valueUnit))
                    InputField(placeholder: "Wert", text: $value, keyboard: .decimalPad, identifier: "checkinValue")
                }
                FieldLabel(text: "Caption (optional)")
                InputField(placeholder: "Wie war's?", text: $caption, identifier: "photoCaption")
                if let from = target.backfillFrom, from < target.today {
                    OtherDayPicker(isOn: $otherDay, day: $day, from: from, to: target.today, zone: target.zone)
                }
                PhotoAudienceHint(target: target)
                if let message = CheckInController.shared.lastError {
                    ErrorLine(message: message)
                }
            }
            .padding(Metrics.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await submit() }
            } label: {
                if submitting { ProgressView().tint(.white) } else { Text("Posten & abhaken") }
            }
            .buttonStyle(PrimaryButtonStyle(fill: Ink.accent, foreground: .white))
            .disabled(!canSubmit)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
            .background(Ink.surface)
            .accessibilityIdentifier("photoPost")
        }
        .background(Ink.surface.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(submitting)
        .task {
            CheckInController.shared.clearError()
        }
    }

    private var canSubmit: Bool {
        if submitting { return false }
        if target.photoRequired && photos.isEmpty { return false }
        if target.valueUnit != nil && ValueEntrySheet.number(value, unit: target.valueUnit) == nil { return false }
        return true
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        let chosenDay = otherDay ? CalendarDate(date: day, in: target.zone) : target.today
        let request = CheckinRequest(
            date: chosenDay,
            value: target.valueUnit != nil ? ValueEntrySheet.number(value, unit: target.valueUnit) : nil,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption)
        if await CheckInController.shared.submit(target, request: request, photos: photos.compactMap(\.image)) {
            dismiss()
        }
    }
}

/// Der Hinweis, wer das Beweisfoto sieht (Vertrag §5.1 - einer der wenigen
/// erlaubten Erklaertexte).
struct PhotoAudienceHint: View {
    let target: CheckInTarget

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: String {
        if let names = target.membersText {
            return "Erscheint im Chat von \(target.name) und in der Timeline von \(names)."
        }
        return "Erscheint im Chat von \(target.name)."
    }
}

/// Wert, Notiz und „Anderer Tag" (Vertrag §5.3). Auch fuer eine
/// Unterbrechung an einem anderen Tag.
struct ValueEntrySheet: View {
    let target: CheckInTarget

    @State private var value = ""
    @State private var note = ""
    @State private var otherDay = false
    @State private var day = Date()
    @State private var submitting = false
    @Environment(\.dismiss) private var dismiss

    private var isBreak: Bool { target.type == .abstinence }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: isBreak ? "Unterbrechung eintragen" : "\(target.name) eintragen") { dismiss() }
                if target.valueUnit != nil && !isBreak {
                    FieldLabel(text: Self.unitTitle(target.valueUnit))
                    InputField(placeholder: "Wert", text: $value, keyboard: .decimalPad, identifier: "checkinValue")
                }
                FieldLabel(text: "Notiz (optional)")
                InputField(placeholder: "Notiz", text: $note, identifier: "checkinNote")
                if let from = target.backfillFrom, from < target.today {
                    OtherDayPicker(isOn: $otherDay, day: $day, from: from, to: target.today, zone: target.zone,
                                   forced: target.valueUnit == nil && !isBreak)
                }
                if let message = CheckInController.shared.lastError {
                    ErrorLine(message: message)
                }
            }
            .padding(Metrics.gutter)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await submit() }
            } label: {
                if submitting { ProgressView().tint(Ink.onInk) } else { Text("Eintragen") }
            }
            .buttonStyle(PrimaryButtonStyle(fill: isBreak ? Ink.danger : Ink.ink,
                                            foreground: isBreak ? .white : Ink.onInk))
            .disabled(!canSubmit)
            .padding(Metrics.gutter)
            .accessibilityIdentifier("checkinSubmit")
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            CheckInController.shared.clearError()
            // Ohne Wert (und bei einer Unterbrechung, die ueber „Anderer Tag …"
            // kommt) heisst das Blatt nur „anderer Tag" - dann gleich an, und
            // gestern ist der naheliegende.
            if target.valueUnit == nil || isBreak {
                otherDay = true
                if let from = target.backfillFrom, target.today.adding(days: -1) >= from {
                    day = target.today.adding(days: -1).startOfDay(in: target.zone)
                }
            }
        }
    }

    private var canSubmit: Bool {
        if submitting { return false }
        if target.valueUnit != nil && !isBreak { return Self.number(value, unit: target.valueUnit) != nil }
        return true
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        let chosenDay = otherDay ? CalendarDate(date: day, in: target.zone) : target.today
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CheckinRequest(
            kind: isBreak ? .break : .done,
            date: chosenDay,
            value: isBreak ? nil : Self.number(value, unit: target.valueUnit),
            note: trimmedNote.isEmpty ? nil : trimmedNote)
        if await CheckInController.shared.submit(target, request: request) {
            dismiss()
        }
    }

    // MARK: - Zahlen

    nonisolated static func unitTitle(_ unit: String?) -> String {
        switch unit?.uppercased() {
        case "COUNT": "Anzahl"
        case "MINUTES": "Minuten"
        case "KM": "Kilometer"
        case "STEPS": "Schritte"
        case "KCAL": "kcal"
        default: unit ?? "Wert"
        }
    }

    /// Liest eine deutsch geschriebene Zahl: „8.200" Schritte, „5,2" km.
    /// Ein einzelner Punkt ist bei Schritten, Anzahl und kcal ein Tausender,
    /// bei km und Minuten ein Komma - so tippt man es jeweils.
    nonisolated static func number(_ text: String, unit: String? = nil) -> Double? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        guard !raw.isEmpty else { return nil }
        let hasComma = raw.contains(",")
        let hasDot = raw.contains(".")
        if hasComma && hasDot {
            raw = raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if hasComma {
            raw = raw.replacingOccurrences(of: ",", with: ".")
        } else if hasDot, ["STEPS", "COUNT", "KCAL"].contains(unit?.uppercased() ?? "") {
            raw = raw.replacingOccurrences(of: ".", with: "")
        }
        guard let number = Double(raw), number.isFinite, number > 0 else { return nil }
        return number
    }

    /// „8200", „5,2".
    nonisolated static func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }
}

/// „Anderer Tag" - ein Tag ab `backfillFrom` bis heute.
struct OtherDayPicker: View {
    @Binding var isOn: Bool
    @Binding var day: Date
    let from: CalendarDate
    let to: CalendarDate
    let zone: TimeZone
    var forced = false

    var body: some View {
        FormCard {
            if !forced {
                ToggleRow(title: "Anderer Tag", isOn: $isOn, identifier: "otherDay")
            }
            if isOn || forced {
                if !forced { FormDivider() }
                DatePicker("Tag", selection: $day,
                           in: from.startOfDay(in: zone)...to.startOfDay(in: zone).addingTimeInterval(86_399),
                           displayedComponents: .date)
                    .font(.system(size: 17, weight: .bold))
                    .environment(\.locale, Locale(identifier: "de_DE"))
                    .environment(\.timeZone, zone)
                    .frame(minHeight: 56)
            }
        }
    }
}
