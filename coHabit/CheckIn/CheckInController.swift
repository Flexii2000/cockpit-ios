import SwiftUI
import UIKit

/// Alles, was zum Abhaken eines Co-Habits gehoert - aus einer Karte, einer
/// Zeile, der Detailseite oder dem Chat (Vertrag §5.3). Aus „Heute" ist nicht
/// alles bekannt (Nachtragsfrist, Zone); dann gibt es eben kein „Anderer Tag".
struct CheckInTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let color: PaletteKey
    let type: CohabitType
    let photoRequired: Bool
    /// `nil` bei Ja/Nein, sonst die Einheit (`KM`, `STEPS` …).
    let valueUnit: String?
    /// Laufpunkte: Dauer und Distanz statt eines Werts (`runEntry`).
    let runEntry: Bool
    let label: String
    /// Wer das Beweisfoto in der Timeline sieht - fuer den Hinweis im Blatt.
    let otherMembers: [String]
    let backfillFrom: CalendarDate?
    let zone: TimeZone
    /// Ueber „Nachtragen …" geoeffnet - das Lauf-Blatt steht dann gleich auf
    /// „Anderer Tag".
    var backfill = false

    init(summary: CohabitSummary, meId: String?) {
        id = summary.ref.id
        name = summary.ref.name
        color = summary.ref.color
        type = summary.ref.type
        photoRequired = summary.photoRequired
        valueUnit = summary.valueUnit
        runEntry = summary.isRunEntry
        label = summary.checkInLabel ?? "Abhaken"
        otherMembers = summary.members.filter { $0.id != meId }.map { $0.shortLabel(me: nil) }
        backfillFrom = nil
        zone = CohabitGroup.zone(for: summary.ref.id) ?? Self.defaultZone
    }

    init(detail: CohabitDetail, meId: String?) {
        id = detail.id
        name = detail.ref.name
        color = detail.ref.color
        type = detail.ref.type
        photoRequired = detail.config.photoRequired
        valueUnit = detail.summary.valueUnit ?? (detail.config.tracking.isValue ? detail.config.tracking.unit : nil)
        runEntry = detail.summary.isRunEntry
        label = detail.summary.checkInLabel ?? "Abhaken"
        otherMembers = detail.members.map(\.person).filter { $0.id != meId }.map { $0.shortLabel(me: nil) }
        backfillFrom = detail.backfillFrom
        zone = TimeZone(identifier: detail.config.timezone) ?? Self.defaultZone
    }

    static let defaultZone = TimeZone(identifier: "Europe/Berlin") ?? .current

    /// Heute in der Zone des Co-Habits - nicht in der des Geraets (Vertrag §2.2).
    var today: CalendarDate { .today(in: zone) }

    /// „Lena und Max" / „Lena, Max und Sara".
    var membersText: String? {
        switch otherMembers.count {
        case 0: nil
        case 1: otherMembers[0]
        default: otherMembers.dropLast().joined(separator: ", ") + " und " + otherMembers.last!
        }
    }
}

/// Oeffnet das passende Blatt oder hakt direkt ab.
@MainActor
@Observable
final class CheckInController {

    static let shared = CheckInController()

    /// Das Beweisfoto-Blatt.
    var photoTarget: CheckInTarget?
    /// Wert, Notiz, anderer Tag.
    var valueTarget: CheckInTarget?
    /// Ein Lauf: Dauer, Distanz, Foto, Caption, anderer Tag.
    var runTarget: CheckInTarget?
    /// Die Rueckfrage vor einer Unterbrechung.
    var breakTarget: CheckInTarget?
    /// Laeuft gerade ein Haken? Dann dreht der Knopf.
    private(set) var busy: Set<String> = []
    /// Die Ablehnung des Dienstes - im offenen Blatt gezeigt, nicht nur als
    /// Meldung oben.
    private(set) var lastError: String?

    /// Woher die Anfragen gehen und wohin sie ohne Netz warten - die Tests
    /// setzen hier einen Stub und einen eigenen Postausgang ein.
    var makeAPI: @MainActor () -> CohabitAPI = { Session.shared.api() }
    var outbox: CohabitOutbox = .shared

    private init() {}

    func clearError() {
        lastError = nil
    }

    /// Was ein Tipp auf „Abhaken"/„Eintragen" oeffnet - von ueberall gleich
    /// (Karte, Zeile, Detailseite, klassische Liste).
    enum Step: Equatable {
        /// Abstinenz: erst die Rueckfrage zur Unterbrechung.
        case confirmBreak
        /// Laufpunkte: das Lauf-Blatt (Dauer, Distanz - und dort auch das
        /// Beweisfoto, falls Pflicht).
        case run
        /// Foto-Pflicht: das Beweisfoto-Blatt.
        case photo
        /// Ein Wert (km, Schritte, Minuten …): das Wert-Blatt.
        case value
        /// Ja/Nein bzw. +1: gleich eintragen.
        case submit
    }

    nonisolated static func step(for target: CheckInTarget) -> Step {
        if target.type == .abstinence { return .confirmBreak }
        // Vor dem Foto: ein Lauf ohne Dauer und Distanz nimmt der Dienst nicht.
        if target.runEntry { return .run }
        if target.photoRequired { return .photo }
        if target.valueUnit != nil { return .value }
        return .submit
    }

    func start(_ target: CheckInTarget) {
        guard !busy.contains(target.id) else { return }
        switch Self.step(for: target) {
        case .confirmBreak: breakTarget = target
        case .run: runTarget = target
        case .photo: photoTarget = target
        case .value: valueTarget = target
        case .submit: Task { await submit(target, request: CheckinRequest(date: target.today)) }
        }
    }

    /// Fuer „Anderer Tag" - auch bei Ja/Nein-Co-Habits.
    func startBackfill(_ target: CheckInTarget) {
        if target.runEntry {
            var target = target
            target.backfill = true
            runTarget = target
        } else if target.photoRequired {
            photoTarget = target
        } else {
            valueTarget = target
        }
    }

    /// Schickt einen Eintrag, mit Foto erst das Foto. Ohne Netz landet beides
    /// im Postausgang; der Knopf zeigt dann eine Uhr.
    ///
    /// - Returns: ob das Blatt zugehen darf (angekommen oder abgelegt).
    @discardableResult
    func submit(_ target: CheckInTarget, request: CheckinRequest, photo: UIImage? = nil) async -> Bool {
        busy.insert(target.id)
        defer { busy.remove(target.id) }
        lastError = nil
        let api = makeAPI()
        var request = request
        var jpeg: Data?
        if let photo {
            guard let data = PhotoEncoding.jpeg(photo) else {
                Toast.shared.show("Das Foto ließ sich nicht lesen.", error: true)
                return false
            }
            jpeg = data
        }
        do {
            if let data = jpeg {
                let upload = try await api.uploadPhoto(jpeg: data, key: UUID().uuidString.lowercased())
                if let photo { PhotoLoader.shared.remember(photo, id: upload.id) }
                request.photoId = upload.id
                jpeg = nil
            }
            let result: CheckinResult = try await api.send("POST", "/cohabits/\(target.id)/checkins", body: request)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Self.announcePoints(result.checkin)
            finished(target, kind: request.kind)
            return true
        } catch CohabitError.offline {
            // Auch ein Lauf: mit Datum gilt er spaeter genauso. Lehnt der
            // Dienst ihn dann ab (Pace), steht das mit Distanz und Dauer in
            // der Leiste (`CohabitOutbox.replay`).
            await outbox.enqueueCheckin(cohabitId: target.id, request: request, photo: jpeg)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Toast.shared.show("Kein Netz – geht raus, sobald wieder Netz da ist.")
            if request.kind == .done { WidgetSync.markDone(target.id) }
            return true
        } catch {
            if await Session.shared.handle(error) { return false }
            lastError = error.localizedDescription
            Toast.shared.show(error)
            return false
        }
    }

    /// Nach einem Lauf: die Punkte gross, die Aufschluesselung darunter -
    /// beides fertig vom Dienst. Andere Eintraege bleiben still wie bisher.
    static func announcePoints(_ checkin: Checkin) {
        guard let run = checkin.run, let points = run.pointsText, !points.isEmpty else { return }
        Toast.shared.show(points, detail: run.breakdownText.flatMap { $0.isEmpty ? nil : $0 })
    }

    private func finished(_ target: CheckInTarget, kind: CheckinKind) {
        DataBus.shared.changed()
        if kind == .done {
            WidgetSync.markDone(target.id)
        } else {
            Task { await WidgetSync.refresh() }
        }
    }
}
