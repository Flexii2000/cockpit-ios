import SwiftUI

// Die Bausteine der Oberflaeche nach den Entwuerfen: grosse Radien,
// Pastellflaechen, Primaerknoepfe in Tinte, Akzent-Violett fuer „+" und den
// Einladungslink (Vertrag §5.1).

enum Metrics {
    static let cardRadius: CGFloat = 24
    static let gutter: CGFloat = 18
    static let buttonHeight: CGFloat = 56
}

extension View {
    /// Eine Karte: Flaeche mit grossem Radius, optional mit angeschnittenem Kreis.
    func card(_ fill: Color = Ink.surface, circle: Color? = nil,
              corner: CornerCircle.Corner = .topTrailing, circleSize: CGFloat = 120,
              padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    fill
                    if let circle {
                        CornerCircle(color: circle, corner: corner, size: circleSize)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
    }

    /// Der Hintergrund jedes Bildschirms.
    func screenBackground() -> some View {
        background(Ink.background.ignoresSafeArea())
    }

    /// Ein Streifen hinter der Statusleiste - beim Scrollen liefe der Inhalt
    /// sonst unter Uhr und Akku durch. In der Hintergrundfarbe ist er in Ruhe
    /// unsichtbar, oben hat der Bildschirm ohnehin diese Farbe.
    func statusBarScrim(_ visible: Bool = true, color: Color = Ink.background) -> some View {
        overlay(alignment: .top) {
            if visible {
                color
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 0)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }
}

/// Voll breit unten, Tinte gefuellt.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Ink.ink
    var foreground: Color = Ink.onInk
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(fill.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Umrandet - „Unterbrechung eintragen", „Ablehnen".
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = Metrics.buttonHeight
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Ink.ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Ink.surface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(Ink.ink, lineWidth: 1.6))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Klein und umrandet - „Einladen", „Profil bearbeiten".
struct SmallOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Ink.surface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(Ink.ink, lineWidth: 1.4))
    }
}

/// Der weisse Kreis fuer Zurueck und das Menue im Kopf der Detailseite.
struct CircleButtonLabel: View {
    let systemImage: String
    var size: CGFloat = 44
    var fill: Color = Ink.surface
    var foreground: Color = Ink.ink

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
    }
}

/// Der runde Abhak-Knopf auf Karten und Zeilen: Kamera bei Foto-Pflicht,
/// sonst ein Haken; eine Uhr, solange ein Haken auf Netz wartet.
struct CheckButtonLabel: View {
    enum Style { case filled, outlined }

    let photo: Bool
    var pending = false
    var done = false
    var size: CGFloat = 52
    var style: Style = .filled

    var body: some View {
        let symbol = pending ? "clock" : (done ? "checkmark" : (photo ? "camera" : "checkmark"))
        Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(style == .filled ? Ink.onInk : Ink.ink)
            .frame(width: size, height: size)
            .background {
                if style == .filled {
                    Circle().fill(Ink.ink.opacity(done ? 0.35 : 1))
                } else {
                    Circle().fill(Ink.surface.opacity(0.001))
                        .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 1.6))
                }
            }
    }
}

/// Ein Chip - Regeln, Filter, Reaktionen.
struct Chip: View {
    let text: String
    var fill: Color = Ink.accentSoft
    var foreground: Color = Ink.ink
    var weight: Font.Weight = .semibold
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(fill, in: Capsule())
    }
}

/// Der Umschalter aus den Entwuerfen: weisse Kapsel, gewaehlt in Tinte.
struct CapsuleSegments<Value: Hashable>: View {
    let options: [(value: Value, title: String, badge: Int?)]
    @Binding var selection: Value
    var height: CGFloat = 40
    var fill: Color = Ink.surface
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(.system(size: compact ? 14 : 15, weight: .bold))
                            .lineLimit(1)
                            .fixedSize()
                        if let badge = option.badge, badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Ink.accent, in: Capsule())
                        }
                    }
                    .foregroundStyle(selected ? Ink.onInk : Ink.ink)
                    .padding(.horizontal, compact ? 14 : 12)
                    .frame(maxWidth: compact ? nil : .infinity)
                    .frame(height: height - 8)
                    .background {
                        if selected { Capsule().fill(Ink.ink) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                // Fest, auch wenn die Beschriftung ein Zaehler ergaenzt („Chat, 2").
                .accessibilityIdentifier("segment-\(option.title)")
            }
        }
        .padding(4)
        .background(fill, in: Capsule())
    }
}

/// „OFFEN HEUTE", „LÄUFT".
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Ink.muted)
            .kerning(0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}

/// Ein Balken mit Spur.
struct ProgressTrack: View {
    let fraction: Double
    var fill: Color = Ink.ink
    var track: Color = Ink.track
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((fraction * 100).rounded())) %")
    }
}

/// Leerer Zustand: ein Satz und ein Knopf (Vertrag §5.1).
struct EmptyState: View {
    let text: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.muted)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Die Meldung des Dienstes, rot hinterlegt.
struct ErrorLine: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Ink.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Ink.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// „Offline · Stand: 30.09., 14:02 · 2 warten" - sobald etwas davon zutrifft
/// (Vertrag §5.1: letzter Stand mit „Stand: …" wie in Healthy).
struct SyncLine: View {
    private var sync: CohabitSync { CohabitSync.shared }

    /// Ob die Leiste gerade etwas zu sagen hat - fuer Aufrufer, die um sie
    /// herum Abstand halten und ohne sie keinen wollen.
    static var hasContent: Bool {
        let sync = CohabitSync.shared
        return !parts(stale: sync.staleSince, pending: sync.pending).isEmpty || sync.lastError != nil
    }

    var body: some View {
        let parts = Self.parts(stale: sync.staleSince, pending: sync.pending)
        if !parts.isEmpty || sync.lastError != nil {
            VStack(alignment: .leading, spacing: 4) {
                if !parts.isEmpty {
                    Label(parts.joined(separator: " · "),
                          systemImage: sync.staleSince != nil ? "wifi.slash" : "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.ink)
                }
                if let error = sync.lastError {
                    HStack(alignment: .top) {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Ink.danger)
                        Spacer(minLength: 4)
                        Button {
                            sync.clearError()
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Ink.muted)
                        .accessibilityLabel("Meldung schließen")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Ink.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("syncLine")
        }
    }

    static func parts(stale: Date?, pending: Int) -> [String] {
        var parts: [String] = []
        if let stale { parts.append("Offline · Stand: " + Formats.stamp(stale)) }
        if pending == 1 { parts.append("1 Änderung wartet") }
        if pending > 1 { parts.append("\(pending) Änderungen warten") }
        return parts
    }
}

/// Diagonale Streifen - Platzhalter fuer ein Foto, das noch laedt, und fuer
/// die Kamera-Vorschau ohne Kamera (Simulator).
struct StripedPlaceholder: View {
    var color: Color = PaletteKey.peach.colors.accent
    var label: String?

    var body: some View {
        ZStack {
            Canvas { context, size in
                let step: CGFloat = 26
                var x: CGFloat = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(path, with: .color(color.opacity(0.28)), lineWidth: 11)
                    x += step
                }
            }
            .background(color.opacity(0.12))
            if let label {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.ink.opacity(0.7))
            }
        }
    }
}
