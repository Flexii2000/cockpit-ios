import SwiftUI

/// Die Wortmarke: kleines „c", grosses „H" in Akzent-Violett, sonst Tinte,
/// sehr fett (Vertrag §5.1).
struct CohabitLogo: View {
    var size: CGFloat = 30

    var body: some View {
        Text("\(Text(verbatim: "co").foregroundStyle(Ink.ink))\(Text(verbatim: "H").foregroundStyle(Ink.accent))\(Text(verbatim: "abit").foregroundStyle(Ink.ink))")
            .font(.system(size: size, weight: .black))
            .kerning(-size * 0.03)
            .accessibilityLabel("coHabit")
    }
}
