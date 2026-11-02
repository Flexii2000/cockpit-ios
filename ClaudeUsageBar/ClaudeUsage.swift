import Foundation

/// Was claude.ai unter `GET /api/organizations/{uuid}/usage` meldet - nur die Teile,
/// die die Menüleiste zeigt. Die Schnittstelle ist die interne von claude.ai (die
/// Seite „Einstellungen > Nutzung“ liest sie), also ohne Vertrag: jedes Feld ist
/// optional, Unbekanntes wird überlesen. Stand der Felder: 02.11.2026.
///
/// ```json
/// { "five_hour": null,
///   "seven_day": {"utilization": 45.0, "resets_at": "2026-11-02T11:00:00.14+00:00"},
///   "limits": [{"kind": "weekly_all", "group": "weekly", "percent": 45, "resets_at": "…"},
///              {"kind": "weekly_scoped", "percent": 12, "scope": {"model": {"display_name": "Fable"}}}],
///   "seven_day_breakdown": {"window_started_at": "…", "as_of": "…",
///                           "rows": [{"key": "claude_code", "display_name": "Claude Code", "percent": 84}]},
///   "spend": {"enabled": false, "used": {"amount_minor": 0, "currency": "USD", "exponent": 2}} }
/// ```
struct ClaudeUsage: Equatable, Sendable {

    /// Das Wochenlimit über alle Modelle - die Zahl in der Menüleiste.
    var weekly: Limit?
    /// Weitere Wochenlimits für einzelne Modelle oder Oberflächen (z. B. Fable).
    var scoped: [Limit]
    /// Das 5-Stunden-Fenster - bei Felix' Abo meldet claude.ai keins (`null`).
    var session: Limit?
    /// Wie sich die Woche auf Claude Code, Chats, Cowork … verteilt (Anteile in %).
    var breakdown: [Share]
    /// Beginn des Wochenfensters - für „Tag 7 von 7“.
    var weekStartedAt: Date?
    /// Zusatznutzung (bezahlte Credits über das Limit hinaus), nur wenn eingeschaltet.
    var extra: Extra?

    struct Limit: Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var percent: Double
        var resetsAt: Date?
    }

    struct Share: Equatable, Sendable, Identifiable {
        var id: String { key }
        var key: String
        var title: String
        var percent: Double
    }

    struct Extra: Equatable, Sendable {
        var used: Double
        var limit: Double?
        var currency: String
    }
}

/// Eine Organisation aus `GET /api/organizations` - gebraucht wird nur die, an der
/// das Abo hängt (Fähigkeit `chat`), nicht die API-Organisation daneben.
struct ClaudeOrganization: Decodable, Equatable, Sendable {
    var uuid: String
    var capabilities: [String]?

    var isChat: Bool { capabilities?.contains("chat") == true }

    /// Die Abo-Organisation: bevorzugt die zuletzt in claude.ai benutzte
    /// (Cookie `lastActiveOrg`), sofern sie Chats kann, sonst die erste mit `chat`.
    static func pick(_ all: [ClaudeOrganization], lastActive: String?) -> ClaudeOrganization? {
        if let lastActive, let match = all.first(where: { $0.uuid == lastActive && $0.isChat }) {
            return match
        }
        return all.first(where: \.isChat) ?? all.first
    }
}

enum ClaudeUsageParseError: Error, Equatable {
    case notJSON
}

extension ClaudeUsage {

    /// Liest die Antwort von `/usage`. Wirft nur, wenn es gar kein JSON-Objekt ist;
    /// fehlende Teile bleiben leer.
    static func parse(_ data: Data) throws -> ClaudeUsage {
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw ClaudeUsageParseError.notJSON
        }

        var weekly: Limit?
        var scoped: [Limit] = []
        var session: Limit?
        for (index, entry) in (raw.limits ?? []).enumerated() {
            guard let percent = entry.percent ?? entry.utilization else { continue }
            let resets = entry.resets_at.flatMap(Self.date)
            switch entry.kind {
            case "weekly_all":
                weekly = Limit(id: "weekly_all", title: "Alle Modelle", percent: percent, resetsAt: resets)
            case "five_hour", "session":
                session = Limit(id: "five_hour", title: "5 Stunden", percent: percent, resetsAt: resets)
            default:
                let title = entry.scope?.title ?? entry.kind ?? "Limit"
                scoped.append(Limit(id: "\(entry.kind ?? "limit")-\(index)-\(title)", title: title,
                                    percent: percent, resetsAt: resets))
            }
        }
        // Ältere Form ohne `limits`: dieselben Zahlen stehen in `seven_day`/`five_hour`.
        if weekly == nil, let week = raw.seven_day, let percent = week.utilization {
            weekly = Limit(id: "weekly_all", title: "Alle Modelle", percent: percent,
                           resetsAt: week.resets_at.flatMap(Self.date))
        }
        if session == nil, let hours = raw.five_hour, let percent = hours.utilization {
            session = Limit(id: "five_hour", title: "5 Stunden", percent: percent,
                            resetsAt: hours.resets_at.flatMap(Self.date))
        }

        let breakdown = (raw.seven_day_breakdown?.rows ?? []).compactMap { row -> Share? in
            guard let key = row.key, let percent = row.percent else { return nil }
            return Share(key: key, title: row.display_name ?? key, percent: percent)
        }

        var extra: Extra?
        if let spend = raw.spend, spend.enabled == true, let used = spend.used?.value {
            extra = Extra(used: used, limit: spend.limit?.value, currency: spend.used?.currency ?? "USD")
        }

        return ClaudeUsage(weekly: weekly, scoped: scoped, session: session, breakdown: breakdown,
                           weekStartedAt: raw.seven_day_breakdown?.window_started_at.flatMap(Self.date),
                           extra: extra)
    }

    /// claude.ai schreibt Mikrosekunden („…T11:00:00.147565+00:00“) - die kann
    /// `ISO8601DateFormatter` nicht, also auf Sekunden gekürzt.
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let rest = text[dot...].drop(while: { $0 == "." || $0.isNumber })
        return formatter.date(from: String(text[..<dot]) + rest)
    }

    /// Wie weit die Woche vorbei ist (0…1) - für die Marke auf dem Balken.
    func weekElapsed(at now: Date = Date()) -> Double? {
        guard let start = weekStartedAt, let end = weekly?.resetsAt, end > start else { return nil }
        return min(max(now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
    }

    // MARK: - Rohform

    private struct Raw: Decodable {
        var five_hour: Window?
        var seven_day: Window?
        var limits: [RawLimit]?
        var seven_day_breakdown: Breakdown?
        var spend: Spend?

        // Ein Teil, der anders aussieht als erwartet, soll nicht die ganze Antwort
        // kippen - claude.ai ändert diese Schnittstelle ohne Ankündigung.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            five_hour = try? container.decodeIfPresent(Window.self, forKey: .five_hour)
            seven_day = try? container.decodeIfPresent(Window.self, forKey: .seven_day)
            limits = (try? container.decodeIfPresent([Lenient<RawLimit>].self, forKey: .limits))?
                .compactMap(\.value)
            seven_day_breakdown = try? container.decodeIfPresent(Breakdown.self, forKey: .seven_day_breakdown)
            spend = try? container.decodeIfPresent(Spend.self, forKey: .spend)
        }

        enum CodingKeys: String, CodingKey {
            case five_hour, seven_day, limits, seven_day_breakdown, spend
        }
    }

    private struct Window: Decodable {
        var utilization: Double?
        var resets_at: String?
    }

    private struct RawLimit: Decodable {
        var kind: String?
        var percent: Double?
        var utilization: Double?
        var resets_at: String?
        var scope: Scope?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try? container.decodeIfPresent(String.self, forKey: .kind)
            percent = try? container.decodeIfPresent(Double.self, forKey: .percent)
            utilization = try? container.decodeIfPresent(Double.self, forKey: .utilization)
            resets_at = try? container.decodeIfPresent(String.self, forKey: .resets_at)
            scope = try? container.decodeIfPresent(Scope.self, forKey: .scope)
        }

        enum CodingKeys: String, CodingKey {
            case kind, percent, utilization, resets_at, scope
        }
    }

    /// `{"model": {"display_name": "Fable"}, "surface": null}` - die Oberfläche
    /// kann auch ein Text sein.
    private struct Scope: Decodable {
        var model: Named?
        var surface: Named?

        var title: String? {
            [model?.name, surface?.name].compactMap { $0 }.first
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            model = try? container.decodeIfPresent(Named.self, forKey: .model)
            surface = try? container.decodeIfPresent(Named.self, forKey: .surface)
        }

        enum CodingKeys: String, CodingKey { case model, surface }
    }

    private struct Named: Decodable {
        var name: String?

        init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                name = text
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? container.decodeIfPresent(String.self, forKey: .display_name))
                ?? (try? container.decodeIfPresent(String.self, forKey: .name))
        }

        enum CodingKeys: String, CodingKey { case display_name, name }
    }

    private struct Breakdown: Decodable {
        var window_started_at: String?
        var rows: [Row]?

        struct Row: Decodable {
            var key: String?
            var display_name: String?
            var percent: Double?
        }
    }

    private struct Spend: Decodable {
        var enabled: Bool?
        var used: Money?
        var limit: Money?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try? container.decodeIfPresent(Bool.self, forKey: .enabled)
            used = try? container.decodeIfPresent(Money.self, forKey: .used)
            limit = try? container.decodeIfPresent(Money.self, forKey: .limit)
        }

        enum CodingKeys: String, CodingKey { case enabled, used, limit }
    }

    /// `{"amount_minor": 1230, "currency": "USD", "exponent": 2}` = 12,30 $.
    private struct Money: Decodable {
        var amount_minor: Double?
        var currency: String?
        var exponent: Int?

        var value: Double? {
            amount_minor.map { $0 / pow(10, Double(exponent ?? 2)) }
        }
    }

    /// Ein Listeneintrag, der nicht passt, fällt weg statt die Liste zu kippen.
    private struct Lenient<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}
