import XCTest
@testable import Healthy

/// Die Antwort des To-Do-Dienstes, so wie sie wirklich aussieht.
final class TodoModelTests: XCTestCase {

    func testDecodesTheBoard() throws {
        let data = """
        {"areas":[{"id":"uni","name":"Uni","position":1,"openCount":2,"hiddenDoneCount":1,
          "todos":[{"id":"t1","title":"Hausarbeit","createdAt":"2026-09-04T10:00:00Z","doneAt":null,
                    "visibleUntil":null,"dueAt":"2026-09-01",
                    "reminders":[{"id":"r1","at":"2026-09-05T08:00:00Z","sentAt":null}],
                    "children":[
                      {"id":"c1","title":"Gliederung","createdAt":"2026-09-04T10:01:00Z",
                       "doneAt":"2026-09-04T11:00:00Z","visibleUntil":"2026-09-07T11:00:00Z",
                       "dueAt":null,"reminders":[],"children":[]}]}]}],
         "includesHidden":false,"hiddenDoneCount":1,"now":"2026-09-04T12:00:00.123456Z"}
        """.data(using: .utf8)!
        let board = try APIClient.decoder().decode(TodoBoard.self, from: data)
        XCTAssertEqual(board.areas.count, 1)
        XCTAssertEqual(board.areas[0].todos[0].children[0].title, "Gliederung")
        XCTAssertTrue(board.areas[0].todos[0].children[0].isDone)
        XCTAssertFalse(board.areas[0].todos[0].isDone)
        XCTAssertNotNil(board.areas[0].todos[0].children[0].visibleUntil)
        XCTAssertEqual(board.hiddenDoneCount, 1)
        let top = board.areas[0].todos[0]
        XCTAssertEqual(top.dueAt?.iso, "2026-09-01")
        XCTAssertTrue(top.isOverdue, "faellig am 1.9., heute ist spaeter, offen: ueberfaellig")
        XCTAssertEqual(top.reminders.count, 1)
        XCTAssertNil(top.reminders[0].sentAt)
    }

    /// Der Link, wie ihn der Dienst seit den Feature-Wuenschen liefert - und
    /// alles, was daran schiefgehen kann. Nichts davon darf das Brett kippen.
    func testLinkIsDecodedLenientlyAndNeverBreaksTheBoard() throws {
        /// `link` ist der rohe JSON-Wert, nil laesst das Feld ganz weg.
        func todo(_ id: String, link: String?, children: String = "") -> String {
            let field = link.map { ",\"link\":\($0)" } ?? ""
            return """
            {"id":"\(id)","title":"\(id)","createdAt":"2026-09-04T10:00:00Z","doneAt":null,
             "visibleUntil":null,"dueAt":null,"reminders":[],"children":[\(children)]\(field)}
            """
        }
        let wish = todo("wish", link: "\"https://fherrmann.com/feature-requests/42\"")
        let todos = [
            todo("healthy", link: "null", children: wish),
            todo("old", link: nil),
            todo("script", link: "\"javascript:alert(1)\""),
            todo("bare", link: "\"fherrmann.com/feature-requests/42\""),
            todo("number", link: "42"),
            todo("empty", link: "\"\""),
            todo("nohost", link: "\"https://\""),
            todo("upper", link: "\"HTTPS://FHERRMANN.COM/X\""),
        ]
        let data = """
        {"areas":[{"id":"server","name":"Server","position":2,"openCount":9,"hiddenDoneCount":0,
          "todos":[\(todos.joined(separator: ","))]}],
         "includesHidden":false,"hiddenDoneCount":0,"now":"2026-09-26T12:00:00Z"}
        """.data(using: .utf8)!
        let board = try APIClient.decoder().decode(TodoBoard.self, from: data)
        let byID = Dictionary(uniqueKeysWithValues: board.areas[0].todos.map { ($0.id, $0) })

        XCTAssertEqual(byID["healthy"]?.children.first?.link,
                       URL(string: "https://fherrmann.com/feature-requests/42"),
                       "auch bei einer Unteraufgabe")
        XCTAssertNil(byID["healthy"]?.link, "null heisst kein Link")
        XCTAssertNil(byID["old"]?.link, "ein Dienst ohne das Feld")
        XCTAssertNil(byID["script"]?.link, "kein fremdes Schema")
        XCTAssertNil(byID["bare"]?.link, "ohne Schema keine Webadresse")
        XCTAssertNil(byID["number"]?.link, "kein Text")
        XCTAssertNil(byID["empty"]?.link)
        XCTAssertNil(byID["nohost"]?.link)
        XCTAssertNotNil(byID["upper"]?.link, "das Schema darf gross sein")
    }

    func testWebLinkTrims() {
        XCTAssertEqual(TodoItem.webLink("  https://fherrmann.com/x \n"), URL(string: "https://fherrmann.com/x"))
        XCTAssertEqual(TodoItem.webLink("http://fherrmann.com"), URL(string: "http://fherrmann.com"))
        XCTAssertNil(TodoItem.webLink(nil))
        XCTAssertNil(TodoItem.webLink("   "))
        XCTAssertNil(TodoItem.webLink("ftp://fherrmann.com/datei"))
    }

    func testReminderDraftCarriesTheZone() throws {
        let draft = ReminderDraft(at: Date(timeIntervalSince1970: 1_788_000_000))
        XCTAssertTrue(draft.at.hasSuffix("Z"), draft.at)
    }
}
