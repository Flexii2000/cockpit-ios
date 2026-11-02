import Foundation

/// Verda (Helsinki, Prepaid) im Stand von `GET /cloud-usage/api/usage`, Feld `verda` -
/// Vertrag: `../cloud-usage/docs/API.md`, Abschnitt „`verda`“.
///
/// Alle Beträge in **Euro**, wie Verda abrechnet (Felix, 02.11.: keine Umrechnung,
/// keine Summe mit AWS). Verda hat keine Abrechnungs-API; der Dienst liest jede
/// Minute das Guthaben, jede Abnahme ist eine Ausgabe, jede Zunahme eine Aufladung.
struct VerdaUsage: Codable, Sendable, Equatable {
    /// Immer `EUR`.
    let currency: String
    /// `YYYY-MM`, in UTC.
    let month: String
    /// Guthaben jetzt.
    let balance: Double
    /// Ausgaben im laufenden Monat - das steht in der Menüleiste.
    let spent: Double
    /// Aufladungen im laufenden Monat.
    let topUps: Double
    /// Das Monatsbudget des Dienstes (Verda selbst hat keins); `nil`, wenn keins gesetzt ist.
    let budget: VerdaBudget?
    /// `spent / budget.limit × 100`, kann über 100 liegen; `nil` ohne Budget.
    let percent: Double?
    /// Alles, was gerade Geld kostet, älteste zuerst.
    let running: [VerdaInstance]
    /// Volumes an keiner laufenden Instanz, die trotzdem kosten - leer ist der Normalfall.
    let volumes: [VerdaVolume]
    let buckets: [VerdaBucket]
    /// Vormonate seit Messbeginn, neuester zuerst, ohne den laufenden.
    let months: [VerdaMonth]
    /// Seit wann der Dienst misst - Ausgaben davor kennt er nicht.
    let trackingSince: Date?
    /// Letzte gelungene Abfrage des Guthabens.
    let checkedAt: Date?
    /// `nil` oder ein kurzer Satz; die Zahlen sind dann der letzte gute Stand.
    let problem: String?
}

struct VerdaBudget: Codable, Sendable, Equatable {
    /// Euro.
    let limit: Double
}

struct VerdaInstance: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    /// Aus den Tags von verda-llm (`server` …); `nil` bei fremden Instanzen.
    let role: String?
    /// Aus den Tags von verda-llm (`ready` …); `nil` bei fremden Instanzen.
    let phase: String?
    let type: String
    /// Rechenzentrum, z. B. `FIN-03`.
    let location: String
    /// `spot` oder `on-demand`.
    let lifecycle: String
    /// Euro laut Verda. Optional gelesen wie bei AWS, damit eine Instanz ohne
    /// Preis die übrigen nicht unlesbar macht.
    let pricePerHour: Double?
    let launchedAt: Date?
    /// Bisher für diese Instanz, je angefangene 10 Minuten.
    let estimate: Double

    var isSpot: Bool { lifecycle == "spot" }
}

struct VerdaVolume: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let sizeGb: Double
    /// Wie Verda ihn meldet, z. B. `detached`.
    let status: String
}

struct VerdaBucket: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let sizeGb: Double

    var id: String { name }
}

struct VerdaMonth: Codable, Sendable, Equatable, Identifiable {
    let month: String
    let spent: Double

    var id: String { month }
}

extension VerdaUsage {

    /// Wie weit der Budget-Balken gefüllt ist (0…1); ohne Budget leer.
    var budgetFraction: Double {
        guard let limit = budget?.limit, limit > 0 else { return 0 }
        return min(max(spent / limit, 0), 1)
    }

    /// Maßstab der Vormonate: das größere von Budget und teuerstem Monat.
    var monthScale: Double {
        max(budget?.limit ?? 0, months.map(\.spent).max() ?? 0, 0.01)
    }

    /// Ob `spent` nur einen Teil des Monats abdeckt - der Dienst misst erst seit
    /// `trackingSince`, und das liegt im laufenden Monat.
    var startedThisMonth: Bool {
        guard let trackingSince else { return false }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month], from: trackingSince)
        guard let year = parts.year, let number = parts.month else { return false }
        return String(format: "%04d-%02d", year, number) == month
    }
}
