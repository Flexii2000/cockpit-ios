import XCTest
@testable import coHabit

/// Typfarben je Person (Vertrag §5.2b, Felix 2026-10-05): zehn Farben, jede
/// Person waehlt je Typ und fuer „automatisch"; ein aelterer Dienst ohne das
/// Feld und unbekannte Werte fallen auf die Vorgaben.
final class TypeColorsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private static let mine = #"{"STREAK":"sky","ABSTINENCE":"coral","GOAL":"periwinkle","CHALLENGE":"butter","AUTOMATIC":"sage"}"#

    /// `/me` mit einem `typeColors` - das Fixture ist das eines aelteren Dienstes.
    private static func me(typeColors: String) -> String {
        Fixtures.me.replacingOccurrences(of: #""canLogout":false,"#, with: #""canLogout":false,"typeColors":\#(typeColors),"#)
    }

    private func ref(_ type: CohabitType, _ auto: String? = nil) -> CohabitRef {
        CohabitRef(id: "x", name: "X", color: .rose, type: type, autoSource: auto)
    }

    // MARK: - Palette

    func testPaletteHasTheTenColoursOfTheContract() throws {
        XCTAssertEqual(PaletteKey.allCases.map(\.rawValue),
                       ["peach", "mint", "periwinkle", "butter", "rose", "aqua", "lavender", "sky", "sage", "coral"],
                       "die Reihenfolge ist die der zwei Reihen auf der Seite „Farben“")
        let expected: [PaletteKey: (UInt32, UInt32, UInt32, UInt32, String)] = [
            .lavender: (0xE6DAF7, 0xB392E6, 0x6A3FB0, 0x3B3150, "Lavendel"),
            .sky: (0xD2E8FA, 0x6AB0EB, 0x1D69A6, 0x253A4E, "Himmelblau"),
            .sage: (0xDDE6D2, 0x9CB585, 0x4D6A38, 0x343D2C, "Salbei"),
            .coral: (0xFFD3CC, 0xF47F6E, 0xB4382A, 0x4E2E2A, "Koralle"),
        ]
        for (key, values) in expected {
            let colors = key.colors
            XCTAssertEqual(colors.surfaceLight, values.0, key.rawValue)
            XCTAssertEqual(colors.accentHex, values.1, key.rawValue)
            XCTAssertEqual(colors.strongHex, values.2, key.rawValue)
            XCTAssertEqual(colors.surfaceDark, values.3, key.rawValue)
            XCTAssertEqual(key.title, values.4)
        }
        XCTAssertEqual(try decode(PaletteKey.self, #""coral""#), .coral)
        XCTAssertEqual(try decode(CohabitRef.self, #"{"id":"c","name":"N","color":"sky","type":"GOAL"}"#).storedColor, .sky)
        XCTAssertEqual(try decode(PaletteKey.self, #""ultraviolet""#), .fallback, "eine unbekannte Farbe sprengt nichts")
    }

    // MARK: - Dekodieren

    func testMeViewWithAndWithoutTypeColors() throws {
        let older = try decode(MeView.self, Fixtures.me)
        XCTAssertNil(older.typeColors, "ein aelterer Dienst schickt das Feld nicht")
        XCTAssertEqual(older.typeColors ?? .defaults, .defaults)

        let me = try decode(MeView.self, Self.me(typeColors: Self.mine))
        let colors = try XCTUnwrap(me.typeColors)
        XCTAssertEqual(colors[.streak], .sky)
        XCTAssertEqual(colors[.abstinence], .coral)
        XCTAssertEqual(colors[.goal], .periwinkle)
        XCTAssertEqual(colors[.challenge], .butter)
        XCTAssertEqual(colors[.automatic], .sage)
        XCTAssertEqual(me.person.id, "felix", "der Rest von /me bleibt, wie er war")

        // Liegt als `cohabit.me` in der App-Gruppe - hin und zurueck, mit allen fuenf.
        let encoded = try APIClient.encoder().encode(me)
        XCTAssertEqual(try APIClient.decoder().decode(MeView.self, from: encoded), me)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["typeColors"] as? [String: String],
                       ["STREAK": "sky", "ABSTINENCE": "coral", "GOAL": "periwinkle", "CHALLENGE": "butter", "AUTOMATIC": "sage"])
    }

    func testUnknownMissingAndBrokenValuesFallBackToTheDefaults() throws {
        let odd = try decode(TypeColors.self, #"{"STREAK":"ultraviolet","GOAL":"coral","HABIT":"sky","ABSTINENCE":null,"CHALLENGE":7}"#)
        XCTAssertEqual(odd[.streak], .peach, "unbekannte Farbe: die Vorgabe des Platzes, nicht PaletteKey.fallback")
        XCTAssertEqual(odd[.goal], .coral)
        XCTAssertEqual(odd[.abstinence], .mint)
        XCTAssertEqual(odd[.challenge], .butter, "keine Zeichenkette")
        XCTAssertEqual(odd[.automatic], .aqua, "fehlt")
        XCTAssertEqual(odd, TypeColors.defaults.setting(.coral, for: .goal))

        // Am Feld soll nie ganz /me scheitern.
        XCTAssertEqual(try decode(MeView.self, Self.me(typeColors: #""sky""#)).typeColors, .defaults)
        XCTAssertNil(try decode(MeView.self, Self.me(typeColors: "null")).typeColors)
    }

    func testWidgetDataWithAndWithoutTypeColors() throws {
        let older = try decode(WidgetData.self, Fixtures.widget)
        XCTAssertNil(older.typeColors)
        let json = Fixtures.widget.replacingOccurrences(of: #""openCount":2,"#, with: #""openCount":2,"typeColors":\#(Self.mine),"#)
        let data = try decode(WidgetData.self, json)
        XCTAssertEqual(data.typeColors?[.streak], .sky)
        XCTAssertEqual(data.cohabits.count, 1)
        // Der Stand der Kachel in der App-Gruppe behaelt sie.
        let roundTrip = try APIClient.decoder().decode(WidgetData.self, from: APIClient.encoder().encode(data))
        XCTAssertEqual(roundTrip.typeColors, data.typeColors)
    }

    /// Die Kachel nimmt die Farben von `/widget`; fehlen sie, die des letzten
    /// `/me` der App, sonst die Vorgaben.
    func testWidgetPrefersItsOwnColoursThenTheAppsThenTheDefaults() throws {
        let stored = CohabitGroup.loadMe()
        addTeardownBlock {
            if let stored { CohabitGroup.saveMe(stored) } else { CohabitGroup.removeMe() }
        }
        let older = try decode(WidgetData.self, Fixtures.widget)
        var fresh = older
        fresh.typeColors = TypeColors.defaults.setting(.lavender, for: .challenge)

        CohabitGroup.removeMe()
        XCTAssertEqual(CohabitGroup.typeColors(for: older), .defaults)
        CohabitGroup.saveMe(try decode(MeView.self, Self.me(typeColors: Self.mine)))
        XCTAssertEqual(CohabitGroup.typeColors(for: older)[.streak], .sky, "aus cohabit.me")
        XCTAssertEqual(CohabitGroup.typeColors(for: fresh)[.challenge], .lavender, "/widget geht vor")
        XCTAssertEqual(CohabitGroup.typeColors(for: fresh)[.streak], .peach)
        let challenge = try XCTUnwrap(fresh.challenge)
        XCTAssertEqual(challenge.ref.typeColor(in: CohabitGroup.typeColors(for: fresh)), .lavender)
    }

    // MARK: - Zuordnung

    func testMappingWithAutomaticBeforeTheType() {
        let colors = TypeColors([.streak: .sky, .automatic: .coral, .goal: .sage])
        XCTAssertEqual(ref(.streak).typeColor(in: colors), .sky)
        XCTAssertEqual(ref(.goal).typeColor(in: colors), .sage)
        XCTAssertEqual(ref(.abstinence).typeColor(in: colors), .mint, "nicht gewaehlt: die Vorgabe")
        XCTAssertEqual(ref(.challenge).typeColor(in: colors), .butter)
        XCTAssertEqual(ref(.streak, "FOOD").typeColor(in: colors), .coral, "Track food ist ein Streak, aber automatisch")
        XCTAssertEqual(ref(.goal, "STEPS_WEEKLY").typeColor(in: colors), .coral)
        XCTAssertEqual(ref(.streak, "SOMETHING_NEW").typeColorSlot, .automatic)
        XCTAssertEqual(ref(.abstinence).typeColorSlot, .abstinence)
    }

    func testSameLookingColoursAreEqual() {
        XCTAssertEqual(TypeColors([.streak: .peach]), .defaults, "die Vorgabe zu waehlen ist keine Abweichung")
        XCTAssertEqual(TypeColors.defaults.setting(.sky, for: .streak).setting(.peach, for: .streak), .defaults)
        XCTAssertNotEqual(TypeColors.defaults.setting(.mint, for: .streak), .defaults)
        XCTAssertEqual(TypeColorSlot.allCases.map(\.title), ["Streak", "Abstinenz", "Ziel", "Challenge", "Automatisch"])
        XCTAssertEqual(TypeColorSlot.allCases.map(\.defaultColor), [.peach, .mint, .periwinkle, .butter, .aqua])
    }

    // MARK: - Speichern

    func testSavingSendsOnlyThatSlot() async throws {
        StubServer.install { _ in .json(200, Self.mine) }
        let saved = try await StubServer.api().saveTypeColor(.sky, for: .streak)
        XCTAssertEqual(saved[.streak], .sky)
        XCTAssertEqual(saved[.automatic], .sage, "zurueck kommen alle fuenf")
        let request = try XCTUnwrap(StubServer.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.path, "/cohabit/api/me/type-colors")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: String])
        XCTAssertEqual(body, ["STREAK": "sky"])
    }

    /// Ein Tipp faerbt sofort um und bleibt, wenn der Dienst zustimmt; lehnt
    /// er ab oder fehlt das Netz, springt die Wahl zurueck und seine Meldung
    /// kommt an.
    @MainActor
    func testChoosingAppliesAtOnceAndRevertsOnFailure() async throws {
        let session = Session.shared
        let before = session.typeColors
        addTeardownBlock { @MainActor in session.apply(before) }
        session.apply(.defaults)

        StubServer.install { _ in .json(200, Self.mine) }
        let ok = await session.chooseTypeColor(.sky, for: .streak, api: StubServer.api())
        XCTAssertNil(ok)
        XCTAssertEqual(session.typeColors[.streak], .sky)
        XCTAssertEqual(session.typeColors[.abstinence], .mint, "nur der gewaehlte Platz uebernimmt die Antwort")
        XCTAssertEqual(ref(.streak).typeColor, .sky, "die App faerbt mit den Farben der Sitzung")
        let model = CreateFlowModel()
        model.config = .draft(.streak)
        XCTAssertEqual(model.cleaned.color, .sky, "ein neues Streak geht in der eigenen Farbe raus")

        StubServer.install { _ in .json(400, #"{"message":"Unbekannte Farbe."}"#) }
        let refused = await session.chooseTypeColor(.coral, for: .streak, api: StubServer.api())
        XCTAssertEqual(refused, "Unbekannte Farbe.")
        XCTAssertEqual(session.typeColors[.streak], .sky, "zurueck auf die vorige Wahl")

        StubServer.install { _ in .offline }
        let offline = await session.chooseTypeColor(.sage, for: .goal, api: StubServer.api())
        XCTAssertEqual(offline, "Kein Netz.")
        XCTAssertEqual(session.typeColors[.goal], .periwinkle)

        StubServer.install { _ in .json(500, "") }
        let unchanged = await session.chooseTypeColor(.sky, for: .streak, api: StubServer.api())
        XCTAssertNil(unchanged, "dieselbe Farbe noch einmal fragt den Dienst nicht")
        XCTAssertTrue(StubServer.requests.isEmpty)
    }
}
