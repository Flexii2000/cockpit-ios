import Foundation

/// Welche Co-Habits die Timeline ausblendet.
///
/// Gemerkt wird je Geraet die Menge der AUSGEBLENDETEN Kennungen, nicht die
/// der gewaehlten: ein neues Co-Habit ist so von selbst dabei. Kennungen, die
/// es unter den aktiven Co-Habits nicht (mehr) gibt - geloescht, archiviert,
/// verlassen -, zaehlen nicht: weder im Knopf noch beim Laden. Archiviertes
/// steht nicht im Blatt; was dort nicht abzuwaehlen ist, darf auch nicht
/// unsichtbar ausgeblendet bleiben.
struct TimelineFilter: Equatable, Sendable {

    var hidden: Set<String> = []

    func isVisible(_ id: String) -> Bool {
        !hidden.contains(id)
    }

    /// Die ausgeblendeten unter den aktiven - das, was gilt.
    func excluded(from cohabits: [CohabitRef]) -> Set<String> {
        Set(cohabits.map(\.id)).intersection(hidden)
    }

    func visibleCount(of cohabits: [CohabitRef]) -> Int {
        cohabits.count - excluded(from: cohabits).count
    }

    func allVisible(_ cohabits: [CohabitRef]) -> Bool {
        excluded(from: cohabits).isEmpty
    }

    /// „Alle Habits", der Name des einen sichtbaren, sonst „2 von 5 Habits"
    /// (auch „0 von 5 Habits").
    func label(for cohabits: [CohabitRef]) -> String {
        let excluded = excluded(from: cohabits)
        if excluded.isEmpty { return "Alle Habits" }
        let visible = cohabits.filter { !excluded.contains($0.id) }
        if visible.count == 1 { return visible[0].name }
        return "\(visible.count) von \(cohabits.count) " + (cohabits.count == 1 ? "Habit" : "Habits")
    }

    mutating func toggle(_ id: String) {
        if hidden.contains(id) {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
    }

    /// „Alle": sind alle an, gehen alle aus; sonst gehen alle an.
    mutating func toggleAll(_ cohabits: [CohabitRef]) {
        let ids = Set(cohabits.map(\.id))
        if allVisible(cohabits) {
            hidden.formUnion(ids)
        } else {
            hidden.subtract(ids)
        }
    }

    /// Fuer `GET /timeline`: `limit=30`, dazu `exclude=a,b` - sortiert, damit der
    /// letzte Stand ohne Netz unter derselben Adresse liegt.
    static func query(exclude: Set<String>, before: String? = nil) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "limit", value: "30")]
        if !exclude.isEmpty {
            query.append(URLQueryItem(name: "exclude", value: exclude.sorted().joined(separator: ",")))
        }
        if let before {
            query.append(URLQueryItem(name: "before", value: before))
        }
        return query
    }
}

extension TimelineFilter {

    static let storageKey = "timeline.hidden"

    static func load(from defaults: UserDefaults = .standard) -> TimelineFilter {
        TimelineFilter(hidden: Set(defaults.stringArray(forKey: storageKey) ?? []))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(hidden.sorted(), forKey: Self.storageKey)
    }

    /// Beim Abmelden: die Auswahl gehoerte zu den Co-Habits der vorigen Person.
    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    #if DEBUG
    /// `COCKPIT_TIMELINE_HIDDEN=c-1,c-2` blendet diese Co-Habits beim Start aus,
    /// `none` keins. Leer laesst den gemerkten Stand stehen - run-simulator.sh
    /// reicht die Variable immer durch, auch ohne Wert.
    static func applyEnvironment(_ defaults: UserDefaults = .standard) {
        guard let raw = ProcessInfo.processInfo.environment["COCKPIT_TIMELINE_HIDDEN"], !raw.isEmpty else { return }
        let ids = raw == "none" ? [] : raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        TimelineFilter(hidden: Set(ids)).save(to: defaults)
    }
    #endif
}
