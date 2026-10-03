import SwiftUI
import UIKit

/// Segmentierter Umschalter, dessen Segmente so breit sind wie ihre
/// Beschriftung.
///
/// Sechs Zeitraeume passen in gleich breiten Segmenten nicht auf ein iPhone:
/// „180 Tage" wurde zu „180 Ta…", waehrend „Alles" Platz uebrig hatte.
/// SwiftUIs `Picker` kennt dafuer keinen Schalter, und die globale
/// Appearance (`UISegmentedControl.appearance()`) haette jeden anderen
/// Umschalter der App mit verzogen - etwa „Zeitraum | Linie" im
/// Highlights-Blatt. Deshalb das UIKit-Steuerelement direkt, nur hier.
struct ContentWidthSegments<Value: Hashable>: UIViewRepresentable {

    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: options.map(title))
        control.apportionsSegmentWidthsByContent = true
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                          for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegmentIndex = options.firstIndex(of: selection) ?? UISegmentedControl.noSegment
    }

    /// Volle angebotene Breite, Hoehe wie das Steuerelement selbst - sonst
    /// schrumpft es auf seine Beschriftungen zusammen.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl,
                      context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ContentWidthSegments

        init(parent: ContentWidthSegments) { self.parent = parent }

        @objc func changed(_ control: UISegmentedControl) {
            let index = control.selectedSegmentIndex
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index]
        }
    }
}
