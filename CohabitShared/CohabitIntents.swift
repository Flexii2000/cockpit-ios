import AppIntents
import Foundation
import WidgetKit

/// Was eine Kachel zeigt - und ob man ihr trauen darf.
enum CohabitWidgetState: Sendable, Equatable {
    case noAccess
    case unreachable
    /// `staleSince`: gesetzt, wenn der Stand nicht frisch vom Dienst kommt.
    case data(WidgetData, staleSince: Date?)

    var data: WidgetData? {
        if case .data(let data, _) = self { return data }
        return nil
    }

    var staleSince: Date? {
        if case .data(_, let stale) = self { return stale }
        return nil
    }
}

/// Holt `GET /widget` - mit dem Token aus der Zugriffsgruppe, ohne Netz der
/// Stand, den App oder Kachel zuletzt in die App-Gruppe gelegt haben.
enum WidgetLoader {

    static func load(timeout: TimeInterval = 12) async -> CohabitWidgetState {
        guard let token = CohabitToken.load() else { return .noAccess }
        let api = CohabitAPI(token: token, timeout: timeout, usesCache: false, replaysOutbox: false)
        do {
            let data: WidgetData = try await api.get("/widget")
            CohabitGroup.saveWidgetData(data)
            return .data(data, staleSince: nil)
        } catch CohabitError.unauthorized {
            return .noAccess
        } catch {
            if let cached = CohabitGroup.loadWidgetData() {
                return .data(cached, staleSince: cached.generatedAt ?? Date())
            }
            return .unreachable
        }
    }
}

// MARK: - Auswahl des Co-Habits (kleine und runde Kachel)

struct CohabitEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Co-Habit")
    static let defaultQuery = CohabitEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CohabitEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CohabitEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CohabitEntity] {
        await all()
    }

    private func all() async -> [CohabitEntity] {
        var data = CohabitGroup.loadWidgetData()
        if data == nil { data = await WidgetLoader.load().data }
        return (data?.cohabits ?? []).map { CohabitEntity(id: $0.ref.id, name: $0.ref.name) }
    }
}

struct SelectCohabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Co-Habit wählen"

    @Parameter(title: "Co-Habit")
    var cohabit: CohabitEntity?

    init() {}
}

// MARK: - Abhaken direkt auf der Kachel

/// Der Haken auf der kleinen Kachel (Vertrag §5.5, `quickCheckIn`): hakt
/// heute ab, ohne die App zu oeffnen. Ohne Netz landet der Eintrag im
/// Postausgang der App-Gruppe, die App schickt ihn spaeter. Die Kachel zeigt
/// sofort „erledigt"; Serie und Quote kommen mit dem naechsten Laden.
struct CheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Abhaken"
    static let isDiscoverable = false

    @Parameter(title: "Co-Habit")
    var cohabitId: String

    init() {}

    init(cohabitId: String) {
        self.cohabitId = cohabitId
    }

    func perform() async throws -> some IntentResult {
        guard let token = CohabitToken.load() else { return .result() }
        // Heute in der Zone des Co-Habits - die App legt sie beim Laden ab.
        let zone = CohabitGroup.zone(for: cohabitId) ?? TimeZone(identifier: "Europe/Berlin") ?? .current
        let request = CheckinRequest(date: .today(in: zone))
        let api = CohabitAPI(token: token, timeout: 15, usesCache: false, replaysOutbox: false)
        do {
            try await api.sendIgnoringResponse("POST", "/cohabits/\(cohabitId)/checkins", body: request)
        } catch CohabitError.offline {
            await CohabitOutbox.shared.enqueueCheckin(cohabitId: cohabitId, request: request, photo: nil)
        } catch {
            // 409: schon erledigt - genau das zeigt die Kachel ohnehin gleich.
        }
        if let data = CohabitGroup.loadWidgetData() {
            CohabitGroup.saveWidgetData(data.markingDone(cohabitId))
        }
        return .result()
    }
}
