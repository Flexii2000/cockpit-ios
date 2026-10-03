import PhotosUI
import SwiftUI
import UIKit

/// Das Beweisfoto-Blatt (Entwurf S. 15): Kamera-Vorschau mit Ausloeser,
/// Galerie, Kamerawechsel; Caption optional; der Hinweis, wer das Foto sieht
/// (Vertrag §5.1); „Posten & abhaken".
struct PhotoCheckInSheet: View {
    let target: CheckInTarget

    @State private var photo: UIImage?
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
                ProofPhotoPicker(photo: $photo, color: target.color)
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
        if target.photoRequired && photo == nil { return false }
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
        if await CheckInController.shared.submit(target, request: request, photo: photo) {
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

/// Kamera-Vorschau mit Ausloeser, Galerie und Kamerawechsel - im
/// Beweisfoto-Blatt und im Lauf-Blatt. Die Kamera laeuft, solange die
/// Vorschau zu sehen ist.
struct ProofPhotoPicker: View {
    @Binding var photo: UIImage?
    let color: PaletteKey

    @State private var camera = CameraController()
    @State private var cameraRunning = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var capturing = false

    private var colors: PaletteColor { color.colors }

    var body: some View {
        preview
            .task { cameraRunning = await camera.start() }
            .onDisappear { camera.stop() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photo = image
                    }
                    pickerItem = nil
                }
            }
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            // Fester Rahmen, Inhalt als overlay - ein Foto mit `scaledToFill`
            // machte das Blatt sonst breiter als den Bildschirm.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .overlay {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .accessibilityIdentifier("chosenPhoto")
                    } else if cameraRunning {
                        CameraPreview(session: camera.session)
                    } else {
                        StripedPlaceholder(color: colors.accent, label: "Kamera-Vorschau")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

            HStack {
                galleryButton
                Spacer()
                if photo != nil {
                    Button {
                        photo = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Color(hex: 0x1C1B2E).opacity(0.85), in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                    }
                    .accessibilityLabel("Anderes Foto")
                } else {
                    Button {
                        Task {
                            capturing = true
                            photo = await camera.capture()
                            capturing = false
                        }
                    } label: {
                        Circle()
                            .fill(Color(hex: 0x1C1B2E))
                            .frame(width: 72, height: 72)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                            .overlay { if capturing { ProgressView().tint(.white) } }
                    }
                    .disabled(!cameraRunning || capturing)
                    .accessibilityLabel("Auslöser")
                    .accessibilityIdentifier("shutter")
                }
                Spacer()
                Button {
                    camera.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Ink.ink)
                        .frame(width: 50, height: 50)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!cameraRunning || photo != nil)
                .opacity(cameraRunning && photo == nil ? 1 : 0.5)
                .accessibilityLabel("Kamera wechseln")
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var galleryButton: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_TEST_PHOTO"] == "1" {
            // Nur fuer UI-Tests ohne Galerie-Zugriff: ein erzeugtes Bild statt
            // der Mediathek. Steht hinter dem Schalter, nicht nur hinter DEBUG.
            Button { photo = Self.testImage } label: { GalleryLabel() }
                .accessibilityLabel("Galerie")
                .accessibilityIdentifier("photoGallery")
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) { GalleryLabel() }
                .accessibilityLabel("Galerie")
                .accessibilityIdentifier("photoGallery")
        }
        #else
        PhotosPicker(selection: $pickerItem, matching: .images) { GalleryLabel() }
            .accessibilityLabel("Galerie")
            .accessibilityIdentifier("photoGallery")
        #endif
    }

    #if DEBUG
    static var testImage: UIImage {
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.95, green: 0.63, blue: 0.48, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.35).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 700, y: -150, width: 700, height: 700))
        }
    }
    #endif
}

/// Der Galerie-Knopf in der Kamera-Vorschau.
private struct GalleryLabel: View {
    var body: some View {
        Image(systemName: "photo")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Ink.ink)
            .frame(width: 50, height: 50)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
