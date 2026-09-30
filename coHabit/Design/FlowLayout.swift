import SwiftUI

/// Chips nebeneinander, bei Bedarf in die naechste Zeile - Regeln, Filter,
/// fruehere Runden.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let size = arrange(subviews, width: width).size
        return CGSize(width: min(size.width, width), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Umbrochen wird nach der vorgeschlagenen Breite wie in sizeThatFits,
        // nicht nach bounds: die sind gerundet und manchmal ein Haar
        // schmaler. Dann rutschte der letzte Chip in eine Zeile ohne
        // reservierte Hoehe und laege auf dem Text darunter
        // (Einladungsdialog).
        let origins = arrange(subviews, width: proposal.width ?? bounds.width).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(subview.sizeThatFits(.unspecified)))
        }
    }

    /// Eine Rechnung fuer Groesse und Platzierung, damit beide gleich umbrechen.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Ein halber Punkt Luft, damit Rundung allein nie umbricht.
            if x > 0, x + size.width > width + 0.5 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            maxX = max(maxX, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (origins, CGSize(width: maxX, height: y + lineHeight))
    }
}
