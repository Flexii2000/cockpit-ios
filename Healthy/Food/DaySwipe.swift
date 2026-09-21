import SwiftUI

/// Wischen zwischen Tagen im Essen-Tab: nach links kommt der naechste Tag,
/// nach rechts der vorige - dasselbe wie die Pfeile in der Leiste.
enum DaySwipe {

    /// Um wie viele Tage ein Wisch blaettert: +1, -1 - oder `nil`, wenn es
    /// keiner war. Zu kurz ist ein Wackler; eher senkrecht als waagerecht war
    /// ein Scrollen der Liste, und das darf nicht nebenbei den Tag wechseln.
    static func step(for translation: CGSize) -> Int? {
        let width = translation.width, height = translation.height
        guard abs(width) > 60, abs(width) > 1.5 * abs(height) else { return nil }
        return width < 0 ? 1 : -1
    }
}

extension View {
    /// Haengt den Tageswechsel an eine Ansicht. `simultaneousGesture`, damit
    /// die Liste darunter weiter senkrecht scrollt, und erst am Ende
    /// ausgewertet: waehrend des Ziehens steht noch nicht fest, was es wird.
    ///
    /// Nicht an alles haengen: Eintragszeilen wischen zum Loeschen, das
    /// Diagramm liest beim Ziehen Werte ab, die Umschalter-Reihe scrollt
    /// seitlich - dort gehoert die Geste dem, was schon da ist.
    func daySwipe(_ step: @escaping (Int) -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if let days = DaySwipe.step(for: value.translation) { step(days) }
            })
    }
}
