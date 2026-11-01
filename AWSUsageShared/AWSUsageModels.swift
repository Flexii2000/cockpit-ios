import Foundation

/// Der Stand von `GET /aws-usage/api/usage` - Vertrag: `../aws-usage/docs/API.md`.
///
/// Gerechnet wird im Dienst: Steuer auf die Kategorien verteilt, Live-Hochrechnung,
/// Prozent am Budget. Die Clients (Vault und die Menüleisten-App) zeigen nur.
struct AWSUsage: Codable, Sendable, Equatable {
    let currency: String
    /// `YYYY-MM`, in UTC wie Cost Explorer.
    let month: String
    /// Laut Vertrag immer gesetzt. Optional gelesen, damit ein Dienst ohne
    /// Budget die Zahlen nicht unlesbar macht - dann fehlt nur der Balken.
    let budget: AWSBudget?
    /// `billed + live` - darauf bezieht sich `percent`.
    let spent: Double
    let billed: Double
    let live: Double
    /// Kann über 100 liegen; `nil`, wenn es kein Budget gibt.
    let percent: Double?
    let forecast: Double?
    /// Immer alle vier, in der Reihenfolge des Dienstes.
    let categories: [AWSCategory]
    let running: [AWSInstance]
    /// Neuester zuerst, ohne den laufenden Monat.
    let months: [AWSMonth]
    let billedAt: Date?
    let liveAt: Date?
    let problem: String?
}

struct AWSBudget: Codable, Sendable, Equatable {
    let name: String
    let limit: Double
}

struct AWSCategory: Codable, Sendable, Equatable, Identifiable {
    let key: String
    let name: String
    /// Enthält `live`.
    let amount: Double
    let live: Double
    let items: [AWSItem]

    var id: String { key }
    /// Was Cost Explorer schon führt.
    var billed: Double { max(0, amount - live) }
}

struct AWSItem: Codable, Sendable, Equatable, Identifiable {
    let label: String
    let amount: Double
    let live: Bool

    var id: String { "\(live ? "live" : "billed")-\(label)" }
}

struct AWSInstance: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let category: String
    let region: String
    let type: String
    /// `spot` oder `on-demand`.
    let lifecycle: String
    /// Ohne Steuer, bis zu vier Nachkommastellen; `nil`, wenn der Dienst den
    /// Preis nicht ermitteln konnte.
    let pricePerHour: Double?
    let launchedAt: Date
    /// Mit Steuer - der Teil, den Cost Explorer noch nicht führt.
    let estimate: Double

    var isSpot: Bool { lifecycle == "spot" }
}

struct AWSMonth: Codable, Sendable, Equatable, Identifiable {
    let month: String
    let total: Double
    /// Immer alle vier Schlüssel.
    let categories: [String: Double]

    var id: String { month }

    /// In der Reihenfolge der Kategorien, unbekannte Schlüssel hinten.
    var parts: [(key: String, amount: Double)] {
        let known = AWSCategoryKey.order.map { ($0.rawValue, categories[$0.rawValue] ?? 0) }
        let unknown = categories.keys
            .filter { AWSCategoryKey(rawValue: $0) == nil }
            .sorted()
            .map { ($0, categories[$0] ?? 0) }
        return (known + unknown).map { (key: $0.0, amount: $0.1) }
    }
}

/// Die vier Kategorien. Der Dienst liefert Name und Reihenfolge selbst mit; hier
/// stehen nur Farbe und die Reihenfolge der Vormonate, die nur Schlüssel kennen.
enum AWSCategoryKey: String, CaseIterable, Sendable {
    case llm, hytale, hosting, other

    static let order: [AWSCategoryKey] = [.llm, .hytale, .hosting, .other]

    var name: String {
        switch self {
        case .llm: "LLM"
        case .hytale: "Hytale"
        case .hosting: "Hosting"
        case .other: "Sonstiges"
        }
    }

    static func name(for key: String) -> String {
        AWSCategoryKey(rawValue: key)?.name ?? key
    }
}

extension AWSUsage {

    /// Was die Teile des Budget-Balkens füllen: je Kategorie der abgerechnete und
    /// der Live-Anteil, als Bruchteil des Budgets. Ohne Budget gilt die Summe als
    /// ganzer Balken. Über 100 % wird von hinten gekappt, damit die Reihenfolge
    /// stehen bleibt.
    func barSegments() -> [AWSBarSegment] {
        let scale = budget.map { $0.limit > 0 ? $0.limit : 0 } ?? 0
        let whole = scale > 0 ? scale : max(spent, 0.000_001)
        var remaining = 1.0
        var result: [AWSBarSegment] = []
        for category in categories {
            for (amount, live) in [(category.billed, false), (category.live, true)] where amount > 0 {
                let fraction = min(amount / whole, remaining)
                guard fraction > 0 else { continue }
                result.append(AWSBarSegment(key: category.key, fraction: fraction, live: live))
                remaining -= fraction
            }
        }
        return result
    }
}

struct AWSBarSegment: Sendable, Equatable, Identifiable {
    let key: String
    let fraction: Double
    let live: Bool

    var id: String { "\(key)-\(live)" }
}

enum AWSUsageCoding {

    /// Spring schreibt `Instant` mit bis zu neun Nachkommastellen, mehr als
    /// `ISO8601DateFormatter` verkraftet - der Bruchteil wird vorher abgeschnitten
    /// (wie in `APIClient.parseInstant`, das es auf dem Mac nicht gibt).
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseInstant(raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Kein ISO-Zeitpunkt: \(raw)"))
            }
            return date
        }
        return decoder
    }

    static func parseInstant(_ raw: String) -> Date? {
        var text = raw
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" }) {
            text.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
