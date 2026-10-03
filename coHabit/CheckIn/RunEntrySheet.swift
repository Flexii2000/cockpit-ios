import SwiftUI
import UIKit

/// Ein Lauf bei Laufpunkten (Vertrag §2.6a): Dauer und Distanz, dann wie
/// gewohnt Beweisfoto (bei Pflicht), Caption, „Anderer Tag"; der Knopf heisst
/// wie `checkInLabel` („Lauf eintragen").
///
/// Punkte und Pace rechnet der Dienst. Lehnt er ab (Pace zu langsam), steht
/// seine Meldung im Blatt und die Eingaben bleiben stehen.
struct RunEntrySheet: View {
    let target: CheckInTarget

    @State private var minutes = ""
    @State private var distance = ""
    @State private var photos: [ProofPhoto] = []
    @State private var caption = ""
    @State private var otherDay = false
    @State private var day = Date()
    @State private var submitting = false
    /// Eine Kennung fuer das ganze Blatt: kam ein Versuch doch an und nur die
    /// Antwort nicht zurueck, legt der naechste keinen zweiten Lauf an.
    @State private var requestId = UUID().uuidString.lowercased()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "\(target.name) eintragen",
                            subtitle: target.photoRequired ? "Beweisfoto erforderlich" : nil) { dismiss() }
                RunInputFields(minutes: $minutes, distance: $distance)
                if target.photoRequired {
                    ProofPhotoPicker(photos: $photos, color: target.color)
                }
                FieldLabel(text: "Caption (optional)")
                InputField(placeholder: "Wie war's?", text: $caption, identifier: "runCaption")
                if let from = target.backfillFrom, from < target.today {
                    OtherDayPicker(isOn: $otherDay, day: $day, from: from, to: target.today, zone: target.zone)
                }
                if target.photoRequired {
                    PhotoAudienceHint(target: target)
                }
                if let message = CheckInController.shared.lastError {
                    ErrorLine(message: message)
                        .accessibilityIdentifier("runError")
                }
            }
            .padding(Metrics.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await submit() }
            } label: {
                if submitting { ProgressView().tint(Ink.onInk) } else { Text(target.label) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
            .background(Ink.background)
            .accessibilityIdentifier("runSubmit")
        }
        .screenBackground()
        .presentationDetents(target.photoRequired ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(submitting)
        .onAppear {
            CheckInController.shared.clearError()
            // Ueber „Nachtragen …": gleich auf einem anderen Tag, gestern zuerst.
            if target.backfill, let from = target.backfillFrom, from < target.today {
                otherDay = true
                let yesterday = target.today.adding(days: -1)
                if yesterday >= from { day = yesterday.startOfDay(in: target.zone) }
            }
        }
    }

    private var canSubmit: Bool {
        if submitting { return false }
        if Self.minutes(minutes) == nil || Self.distance(distance) == nil { return false }
        if target.photoRequired && photos.isEmpty { return false }
        return true
    }

    private func submit() async {
        guard let durationMinutes = Self.minutes(minutes), let distanceKm = Self.distance(distance) else { return }
        submitting = true
        defer { submitting = false }
        let chosenDay = otherDay ? CalendarDate(date: day, in: target.zone) : target.today
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = CheckinRequest(id: requestId, date: chosenDay, caption: trimmed.isEmpty ? nil : trimmed,
                                     durationMinutes: durationMinutes, distanceKm: distanceKm)
        if await CheckInController.shared.submit(target, request: request,
                                                 photos: target.photoRequired ? photos.compactMap(\.image) : []) {
            dismiss()
        }
    }

    // MARK: - Eingaben

    /// Ganze Minuten, wie getippt („35") - kein Komma, die Dauer zaehlt in
    /// ganzen Minuten.
    nonisolated static func minutes(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        return value
    }

    /// km, deutsch geschrieben („5,8"; ein Punkt gilt als Komma).
    nonisolated static func distance(_ text: String) -> Double? {
        ValueEntrySheet.number(text, unit: "KM")
    }
}

/// Dauer und Distanz eines Laufs nebeneinander - im Lauf-Blatt und beim
/// Bearbeiten eines eigenen Laufs.
struct RunInputFields: View {
    @Binding var minutes: String
    @Binding var distance: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(text: "Dauer")
                UnitInputField(placeholder: "0", text: $minutes, unit: "Min.", keyboard: .numberPad,
                               identifier: "runMinutes")
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(text: "Distanz")
                UnitInputField(placeholder: "0,0", text: $distance, unit: "km", keyboard: .decimalPad,
                               identifier: "runDistance")
            }
        }
    }
}
