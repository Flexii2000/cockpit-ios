import Foundation

/// Ein Wert im Logbook von Healthy, sofort gezeigt und spaeter geschickt - je
/// Tipp einer (Vertrag `HEALTHY-CONTRACT.md` §4.2). Je Tag und Verhaltensweise
/// gilt der neueste; `nil` macht die Zeile wieder offen.
///
/// Zum Leeren kein DELETE: ein wartendes DELETE liefe nach einem neueren Wert
/// hinterher und loeschte ihn. `{"value": null}` an dieselbe Adresse faellt
/// dagegen beim Zusammenfassen mit dem Wert davor zusammen.
enum LogbookChange: Codable, Equatable, Sendable {
    case setValue(date: CalendarDate, behaviorId: String, value: Double?)

    var date: CalendarDate {
        switch self {
        case .setValue(let date, _, _): date
        }
    }

    var behaviorId: String {
        switch self {
        case .setValue(_, let behaviorId, _): behaviorId
        }
    }

    var value: Double? {
        switch self {
        case .setValue(_, _, let value): value
        }
    }

    /// Eine Zeile an einem Tag: „2026-10-12/b-1a2b3c4d“.
    static func key(_ date: CalendarDate, _ behaviorId: String) -> String {
        date.iso + "/" + behaviorId
    }

    var target: String? { Self.key(date, behaviorId) }

    /// Wie ein Haken: der letzte Stand gilt, was wartet, ersetzt der neue.
    var role: PendingRole { .state }

    var request: PendingRequest {
        PendingRequest(method: "PUT", path: "/api/logbook/days/\(date.iso)/values/\(behaviorId)",
                       body: Self.body(value))
    }

    /// `{"value": null}` ausdruecklich - ein leeres Objekt saehe aus wie ein Versehen.
    static func body(_ value: Double?) -> Data {
        guard let value, let data = try? APIClient.encoder().encode(["value": value]) else {
            return Data(#"{"value":null}"#.utf8)
        }
        return data
    }

    /// Nennt Verhalten und Tag: „„Verhalten A“ am 11.10. ließ sich nicht eintragen: …“.
    func notice(label: String, status: Int, message: String?) -> PendingNotice {
        let row = "„\(label)“ am " + String(format: "%02d.%02d.", date.day, date.month)
        if status == 404 {
            return PendingNotice(text: "„\(label)“ gibt es im Logbook nicht mehr.", isInfo: true)
        }
        return .error("\(row) ließ sich nicht eintragen", message, status: status)
    }
}
