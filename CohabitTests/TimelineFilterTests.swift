import XCTest
@testable import coHabit

/// Der Filter der Timeline: was der Knopf sagt, was gemerkt wird, und dass
/// gemerkt wird, was AUSGEBLENDET ist - ein neues Co-Habit ist von selbst dabei.
final class TimelineFilterTests: XCTestCase {

    private func ref(_ id: String, _ name: String, _ color: PaletteKey = .peach) -> CohabitRef {
        CohabitRef(id: id, name: name, color: color, type: .streak)
    }

    private lazy var laufen = ref("c-a", "Laufen")
    private lazy var lesen = ref("c-b", "Lesen", .mint)
    private lazy var zucker = ref("c-c", "Ohne Zucker", .rose)
    private lazy var kochen = ref("c-d", "Wer kocht öfter?", .butter)

    func testNothingHiddenReadsAllHabits() {
        let filter = TimelineFilter()
        XCTAssertEqual(filter.label(for: [laufen, lesen, zucker]), "Alle Habits")
        XCTAssertEqual(filter.label(for: []), "Alle Habits")
        XCTAssertTrue(filter.allVisible([laufen, lesen]))
    }

    func testExactlyOneVisibleReadsItsName() {
        let filter = TimelineFilter(hidden: ["c-a", "c-c"])
        XCTAssertEqual(filter.label(for: [laufen, lesen, zucker]), "Lesen")
    }

    func testOtherwiseItCounts() {
        XCTAssertEqual(TimelineFilter(hidden: ["c-a", "c-b"]).label(for: [laufen, lesen, zucker, kochen]),
                       "2 von 4 Habits")
        XCTAssertEqual(TimelineFilter(hidden: ["c-a", "c-b", "c-c"]).label(for: [laufen, lesen, zucker]),
                       "0 von 3 Habits")
        XCTAssertEqual(TimelineFilter(hidden: ["c-a"]).label(for: [laufen]), "0 von 1 Habit")
    }

    /// Geloescht, archiviert, verlassen: eine gemerkte Kennung, die es unter den
    /// aktiven nicht gibt, zaehlt nicht - und wird auch nicht ausgeblendet.
    func testUnknownIDsDoNotCount() {
        let filter = TimelineFilter(hidden: ["c-gone", "c-b"])
        XCTAssertEqual(filter.excluded(from: [laufen, lesen, zucker]), ["c-b"])
        XCTAssertEqual(filter.visibleCount(of: [laufen, lesen, zucker]), 2)
        XCTAssertEqual(filter.label(for: [laufen, lesen, zucker]), "2 von 3 Habits")
        XCTAssertEqual(TimelineFilter(hidden: ["c-gone"]).label(for: [laufen, lesen]), "Alle Habits")
        XCTAssertTrue(TimelineFilter(hidden: ["c-gone"]).allVisible([laufen, lesen]))
    }

    /// Gemerkt sind die ausgeblendeten - wer neu dazukommt, ist angehakt.
    func testANewCohabitAppearsByItself() {
        let filter = TimelineFilter(hidden: ["c-a"])
        XCTAssertEqual(filter.label(for: [laufen, lesen]), "Lesen")
        XCTAssertTrue(filter.isVisible("c-d"))
        XCTAssertEqual(filter.label(for: [laufen, lesen, kochen]), "2 von 3 Habits")
        XCTAssertEqual(filter.excluded(from: [laufen, lesen, kochen]), ["c-a"])
    }

    /// Ein Haken an und aus; „Alle": sind alle an, gehen alle aus, sonst alle an.
    func testTogglingOneAndAll() {
        var filter = TimelineFilter()
        filter.toggle("c-b")
        XCTAssertFalse(filter.isVisible("c-b"))
        filter.toggle("c-b")
        XCTAssertTrue(filter.isVisible("c-b"))

        let all = [laufen, lesen, zucker]
        filter.toggleAll(all)
        XCTAssertEqual(filter.visibleCount(of: all), 0, "alle an - also gehen alle aus")
        filter.toggle("c-a")
        filter.toggleAll(all)
        XCTAssertTrue(filter.allVisible(all), "nicht alle an - also gehen alle an")

        // Eine alte Kennung bleibt gemerkt, stoert „Alle" aber nicht.
        var stale = TimelineFilter(hidden: ["c-gone"])
        stale.toggleAll(all)
        XCTAssertEqual(stale.visibleCount(of: all), 0)
    }

    func testRemembersTheHiddenPerDevice() throws {
        let suite = "timeline-filter-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(TimelineFilter.load(from: defaults), TimelineFilter(), "anfangs ist alles sichtbar")
        TimelineFilter(hidden: ["c-b", "c-a"]).save(to: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: TimelineFilter.storageKey), ["c-a", "c-b"])
        XCTAssertEqual(TimelineFilter.load(from: defaults).hidden, ["c-a", "c-b"])
        TimelineFilter.clear(defaults)
        XCTAssertEqual(TimelineFilter.load(from: defaults), TimelineFilter())
    }

    /// `exclude` kommagetrennt und sortiert - dieselbe Auswahl, dieselbe Adresse
    /// (der letzte Stand ohne Netz liegt unter ihr).
    func testQuery() {
        XCTAssertEqual(TimelineFilter.query(exclude: []), [URLQueryItem(name: "limit", value: "30")])
        XCTAssertEqual(TimelineFilter.query(exclude: ["c-b", "c-a"], before: "e9"), [
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "exclude", value: "c-a,c-b"),
            URLQueryItem(name: "before", value: "e9"),
        ])
    }
}

/// Die Timeline gegen einen Dienst im Speicher: was sie ausblendet, wann sie
/// gar nicht erst laedt, und was als gesehen gilt.
@MainActor
final class TimelineStoreTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "timeline-store-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        OfflineCache.clear()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private static func summary(_ id: String, _ name: String) -> String {
        Fixtures.summary.replacingOccurrences(
            of: Fixtures.ref, with: #"{"id":"\#(id)","name":"\#(name)","color":"peach","type":"STREAK"}"#)
    }

    /// `/cohabits` mit Laufen (c-a) und Lesen (c-b), die Timeline aus den
    /// Fixtures, das Gesehen-Melden ohne Inhalt.
    private func install() {
        let list = "[" + Self.summary("c-a", "Laufen") + "," + Self.summary("c-b", "Lesen") + "]"
        StubServer.install { request in
            switch request.path {
            case "/cohabit/api/cohabits": .json(200, list)
            case "/cohabit/api/timeline": .json(200, Fixtures.timeline)
            case "/cohabit/api/timeline/seen": .json(204, "")
            default: .json(404, #"{"message":"unbekannt"}"#)
            }
        }
    }

    private func store(hidden: Set<String>) -> TimelineStore {
        TimelineFilter(hidden: hidden).save(to: defaults)
        return TimelineStore(makeAPI: { ClassicStoreTests.stubAPI() }, defaults: defaults)
    }

    /// Die Abfragen der Timeline-Seiten (`limit=30`) - ohne die eine ungefilterte
    /// (`limit=1`), mit der das neueste Ereignis als gesehen gemeldet wird.
    private func timelineQueries(limit: String = "30") -> [[String: String]] {
        StubServer.requests.filter { $0.path == "/cohabit/api/timeline" }.map { request in
            let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }
        .filter { $0["limit"] == limit }
    }

    /// Ausgeblendet wird nur, was es unter den aktiven gibt; die geloeschte
    /// Kennung zaehlt nicht. Ein Sichtbarer - der Knopf nennt ihn beim Namen.
    func testExcludesOnlyTheHiddenAmongTheActive() async {
        install()
        let store = store(hidden: ["c-b", "c-gone"])
        await store.load()
        XCTAssertEqual(timelineQueries().last?["exclude"], "c-b")
        XCTAssertEqual(store.excluded, ["c-b"])
        XCTAssertEqual(store.filterLabel, "Laufen")
        XCTAssertTrue(store.isFiltered)
        XCTAssertEqual(store.items.map(\.id), ["e1", "e2"])
    }

    /// Nichts ausgeblendet: kein `exclude`, „Alle Habits", und das neueste
    /// Ereignis der Liste gilt als gesehen - wie bisher.
    func testUnfilteredMarksTheNewestShownEventAsSeen() async throws {
        install()
        let store = store(hidden: [])
        await store.load()
        XCTAssertNil(timelineQueries().first?["exclude"])
        XCTAssertEqual(store.filterLabel, "Alle Habits")
        XCTAssertFalse(store.isFiltered)
        let seen = try XCTUnwrap(StubServer.requests.first { $0.path == "/cohabit/api/timeline/seen" })
        XCTAssertEqual(seen.json?["lastEventId"] as? String, "e1")
    }

    /// Gefiltert gilt das neueste Ereignis ueberhaupt als gesehen - sonst
    /// stuende „neue Beweisfotos" auf „Heute" fuer immer da.
    func testFilteredMarksTheNewestEventOverallAsSeen() async throws {
        install()
        let store = store(hidden: ["c-a"])
        await store.load()
        XCTAssertEqual(timelineQueries().last?["exclude"], "c-a")
        let newest = timelineQueries(limit: "1")
        XCTAssertEqual(newest.count, 1, "das neueste Ereignis ohne Filter nachgefragt")
        XCTAssertNil(newest.first?["exclude"])
        XCTAssertNotNil(StubServer.requests.first { $0.path == "/cohabit/api/timeline/seen" })
    }

    /// Alles ausgeblendet: keine Timeline, „0 von 2 Habits" - und sobald die
    /// Liste bekannt ist, fragt sie gar nicht erst.
    func testNothingSelectedLoadsNoTimeline() async {
        install()
        let store = store(hidden: ["c-a", "c-b"])
        await store.load()
        XCTAssertTrue(store.nothingSelected)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.filterLabel, "0 von 2 Habits")
        let before = timelineQueries().count
        await store.load()
        XCTAssertEqual(timelineQueries().count, before, "nichts gewaehlt - nichts zu laden")
        XCTAssertNil(StubServer.requests.first { $0.path == "/cohabit/api/timeline/seen" })
    }

    /// Ein Haken im Blatt wird sofort gemerkt; nach dem Neustart (neuer Store)
    /// gilt dieselbe Auswahl, und Blaettern behaelt den Filter.
    func testTogglingIsRememberedAndPagingKeepsTheFilter() async {
        install()
        let store = store(hidden: [])
        await store.load()
        await store.toggle("c-b")
        XCTAssertEqual(defaults.stringArray(forKey: TimelineFilter.storageKey), ["c-b"])

        let restarted = TimelineStore(makeAPI: { ClassicStoreTests.stubAPI() }, defaults: defaults)
        await restarted.load()
        XCTAssertEqual(restarted.filterLabel, "Laufen")
        XCTAssertEqual(timelineQueries().last?["exclude"], "c-b")

        let more = Fixtures.timeline.replacingOccurrences(of: #""hasMore":false"#, with: #""hasMore":true"#)
        let list = "[" + Self.summary("c-a", "Laufen") + "," + Self.summary("c-b", "Lesen") + "]"
        StubServer.install { request in
            request.path == "/cohabit/api/cohabits" ? .json(200, list) : .json(200, more)
        }
        await restarted.load()
        await restarted.loadMore()
        XCTAssertEqual(timelineQueries().last?["before"], "e2")
        XCTAssertEqual(timelineQueries().last?["exclude"], "c-b")
    }
}
