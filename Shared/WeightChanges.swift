import Foundation

/// Ein Gewicht von Hand, sofort gezeigt („82,4 kg am 12.10. – wartet“) und
/// spaeter geschickt (Runde 4 der Aenderungen vom 12.10.). Je Tag gilt das
/// neueste - der Dienst ersetzt den Wert des Tages ohnehin. Die Kacheln rechnet
/// weiter der Dienst; bis er geantwortet hat, zeigen sie den alten Stand.
///
/// Der Abgleich mit Apple Health geht nicht hier hindurch: er merkt sich selbst,
/// was angekommen ist, und versucht es beim naechsten Lauf noch einmal.
enum WeightChange: Codable, Equatable, Sendable {
    case add(date: CalendarDate, weightKg: Double)

    var date: CalendarDate {
        switch self {
        case .add(let date, _): date
        }
    }

    var weightKg: Double {
        switch self {
        case .add(_, let weightKg): weightKg
        }
    }

    /// Je Tag eine Zeile: „weight/2026-10-12“.
    var target: String? { "weight/" + date.iso }

    var role: PendingRole { .state }

    var request: PendingRequest {
        PendingRequest(method: "POST", path: "/api/weight",
                       body: try? APIClient.encoder().encode(Body(date: date, weightKg: weightKg)))
    }

    /// „Das Gewicht vom 12.10. wurde nicht eingetragen: <Grund>“.
    func notice(label: String, status: Int, message: String?) -> PendingNotice {
        .error("Das Gewicht vom " + String(format: "%02d.%02d.", date.day, date.month) + " wurde nicht eingetragen",
               message, status: status)
    }

    /// Wie `NewWeightRequest` beim Eintragen von Hand: ohne `keepExisting`, der
    /// Wert ersetzt den des Tages.
    private struct Body: Encodable {
        let date: CalendarDate
        let weightKg: Double
    }
}
