import SwiftUI

/// Ein Wert in der Sprechblase am Diagramm.
struct CalloutEntry: Identifiable, Sendable {
    let label: String
    let value: String
    let color: Color

    var id: String { label }
}

/// Die Sprechblase, die beim Ziehen ueber ein Diagramm erscheint.
///
/// Zeigt alle gerade sichtbaren Serien fuer einen Tag - dieselbe Auswahl wie
/// die Weboberflaeche, die dafuer Chart.js im Modus `index` benutzt. Auf einem
/// Touchgeraet fehlt bewusst der Schleier ueber dem Mittelungsfenster, den es
/// im Browser gibt: dort fuehrt ein Mauszeiger, hier verdeckt der Finger die
/// Stelle ohnehin.
struct ChartCallout: View {

    let title: String
    let entries: [CalloutEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 6, height: 6)
                    Text(entry.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(entry.value)
                        .font(.caption.monospacedDigit().weight(.medium))
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        .shadow(radius: 2, y: 1)
        .fixedSize()
    }
}

/// Findet den Tag, der einem angetippten Zeitpunkt am naechsten liegt.
///
/// Eigene Funktion, damit sie geprueft werden kann: eine Ziehgeste laesst sich
/// im Simulator nicht ausloesen, die Auswahl also nicht am Bild kontrollieren.
enum ChartSelection {

    static func nearestDay(to date: Date, in days: [CalendarDate]) -> CalendarDate? {
        days.min { first, second in
            abs(first.startOfDay().timeIntervalSince(date))
                < abs(second.startOfDay().timeIntervalSince(date))
        }
    }
}
