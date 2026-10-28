import ActivityKit
import AppIntents
import Foundation

/// Die Live-Aktivitaet eines laufenden Timers (Vertrag §2.4b, §5.2d): Name,
/// laufende Zeit und Stopp auf Sperrbildschirm und Dynamic Island.
///
/// In `CohabitShared/`, weil die Kachel-Erweiterung sie zeigt und die App sie
/// startet. Hochgezaehlt wird von selbst (`Text(timerInterval:)`) - die App
/// muss dafuer nicht laufen.
struct CohabitTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }

    let cohabitId: String
    let name: String
    /// Die Typfarbe der Person (`PaletteKey`), damit die Aktivitaet aussieht wie die Karte.
    let color: String
}

/// Der Stopp-Knopf der Live-Aktivitaet. Als `LiveActivityIntent` laeuft er im
/// Prozess der App (auch im Hintergrund), nicht in der Erweiterung.
struct StopCohabitTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Timer stoppen"
    static let isDiscoverable = false

    @Parameter(title: "Co-Habit")
    var cohabitId: String

    init() {}

    init(cohabitId: String) {
        self.cohabitId = cohabitId
    }

    func perform() async throws -> some IntentResult {
        await CohabitTimerStop.stop(cohabitId: cohabitId, at: Date())
        return .result()
    }
}

/// Stoppt einen Timer ohne Oberflaeche - fuer den Knopf der Live-Aktivitaet.
/// Ohne Netz wartet der Stopp mit seiner Tippzeit im Postausgang. Lehnt der
/// Dienst ab (lief ueber 24 Stunden), bleibt die Aktivitaet stehen: die App
/// zeigt beim naechsten Oeffnen, warum, und dort laesst er sich verwerfen.
enum CohabitTimerStop {

    /// Die App hoert darauf und laedt neu - der Knopf laeuft in ihrem Prozess.
    static let stopped = Notification.Name("CohabitTimerStopped")

    static func stop(cohabitId: String, at date: Date) async {
        guard let token = CohabitToken.load() else { return }
        let request = TimerStopRequest(stoppedAt: date)
        let api = CohabitAPI(token: token, timeout: 15, usesCache: false, replaysOutbox: false)
        do {
            try await api.sendIgnoringResponse("POST", "/cohabits/\(cohabitId)/timer/stop", body: request)
        } catch CohabitError.offline {
            await CohabitOutbox.shared.enqueueTimerStop(cohabitId: cohabitId, request: request)
        } catch CohabitError.server(status: 409, _) {
            // Laeuft schon nicht mehr (etwa im Web gestoppt) - die Aktivitaet kann weg.
        } catch {
            return
        }
        await end(cohabitId: cohabitId)
        await MainActor.run {
            NotificationCenter.default.post(name: stopped, object: cohabitId)
        }
    }

    /// Nacheinander und im selben Kontext: `Activity` ist nicht Sendable.
    static func end(cohabitId: String) async {
        for activity in Activity<CohabitTimerAttributes>.activities where activity.attributes.cohabitId == cohabitId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
