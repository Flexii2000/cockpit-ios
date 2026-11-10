import SwiftUI

extension MacroTone {

    /// Dieselben Verlaeufe wie in der Weboberflaeche (`#gauge-…` in
    /// `food/.../index.html`) - dieselbe Zahl soll in App und Browser nicht
    /// unterschiedlich eingefaerbt sein.
    ///
    /// Eigene Datei, weil `Color(hex:)` auf der Uhr nicht baut
    /// (`_watch_excludes` in project.yml).
    var gradient: [Color] {
        switch self {
        case .neutral, .near: [Color(hex: 0x8BA3FF), Color(hex: 0x4C6EF5)]
        case .good:           [Color(hex: 0x8EE09B), Color(hex: 0x43A75A)]
        case .warn:           [Color(hex: 0xFFD68A), Color(hex: 0xF59F26)]
        case .bad:            [Color(hex: 0xFF938F), Color(hex: 0xDC3C39)]
        }
    }
}
