import SwiftUI

// Formularzeilen im Stil der Entwuerfe (Anlegen Schritt 2, Profil): weisse
// Karten mit Zeilen, Beschriftung links, Wert oder Schalter rechts.

/// Eine weisse Karte mit Zeilen, getrennt durch feine Linien.
struct FormCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

struct FormDivider: View {
    var body: some View {
        Rectangle().fill(Ink.track).frame(height: 1)
    }
}

/// Beschriftung links, Wert rechts, Pfeil - oeffnet etwas.
struct FormRow<Trailing: View>: View {
    let title: String
    var titleColor: Color = Ink.ink
    var chevron = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(titleColor)
            Spacer(minLength: 8)
            trailing
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension FormRow where Trailing == EmptyView {
    init(title: String, titleColor: Color = Ink.ink, chevron: Bool = true) {
        self.title = title
        self.titleColor = titleColor
        self.chevron = chevron
        self.trailing = EmptyView()
    }
}

/// Eine Zeile mit Schalter.
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var identifier: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Ink.ink)
        }
        .tint(Ink.accent)
        .frame(minHeight: 56)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Der Wert rechts in einer Zeile.
struct RowValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Ink.muted)
            .lineLimit(1)
    }
}

/// Ueberschrift ueber einem Feld - „Name", „Farbe".
struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Ink.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ein Eingabefeld in Akzent zart, wie „Laufen" im Entwurf.
struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var identifier: String?
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Ink.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Ink.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.accent.opacity(0.18)))
            .accessibilityIdentifier(identifier ?? placeholder)
    }
}

/// Minus, Wert, Plus - „3× pro Woche".
struct StepperCapsule: View {
    let text: String
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack {
            Button(action: decrease) {
                Image(systemName: "minus").font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 44, height: 44)
                    .background(Ink.surface, in: Circle())
            }
            .disabled(!canDecrease)
            .opacity(canDecrease ? 1 : 0.4)
            .accessibilityLabel("Weniger")
            Spacer()
            Text(text)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Ink.ink)
            Spacer()
            Button(action: increase) {
                Image(systemName: "plus").font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 44, height: 44)
                    .background(Ink.surface, in: Circle())
            }
            .disabled(!canIncrease)
            .opacity(canIncrease ? 1 : 0.4)
            .accessibilityLabel("Mehr")
        }
        .padding(6)
        .background(Ink.track, in: Capsule())
    }
}

/// Kopf eines Blatts: Titel und das runde X.
struct SheetHeader: View {
    let title: String
    var subtitle: String?
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.heading(24))
                    .foregroundStyle(Ink.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.muted)
                }
            }
            Spacer()
            Button(action: close) {
                CircleButtonLabel(systemImage: "xmark", size: 40, fill: Ink.accentSoft)
            }
            .accessibilityLabel("Schließen")
            .accessibilityIdentifier("sheetClose")
        }
    }
}
