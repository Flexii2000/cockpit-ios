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

    func testReminderDraftCarriesTheZone() throws {
        let draft = ReminderDraft(at: Date(timeIntervalSince1970: 1_788_000_000))
        XCTAssertTrue(draft.at.hasSuffix("Z"), draft.at)
    }
}
