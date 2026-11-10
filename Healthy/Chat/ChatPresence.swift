import Foundation
import os

/// Ob der Chat gerade zu sehen ist - gefragt vom Rueckruf der Mitteilungen,
/// der auf keinem bestimmten Thread laeuft: steht der Chat offen, braucht die
/// Meldung „Deine Antwort ist da.“ kein Banner mehr.
final class ChatPresence: Sendable {

    static let shared = ChatPresence()

    private let visible = OSAllocatedUnfairLock(initialState: false)

    private init() {}

    var isVisible: Bool { visible.withLock { $0 } }

    func set(_ value: Bool) { visible.withLock { $0 = value } }
}
