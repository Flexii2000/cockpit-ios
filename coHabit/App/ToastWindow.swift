import SwiftUI
import UIKit

/// Ein eigenes Fenster fuer die Meldung oben - ueber allen Blaettern.
///
/// Im Wurzel-View laege sie unter jedem offenen Blatt: ein Fehler beim Posten
/// eines Beweisfotos waere genau dann unsichtbar, wenn man ihn braucht. Das
/// Fenster laesst jede Beruehrung durch, die nicht die Meldung trifft.
@MainActor
enum ToastWindow {

    private static var window: UIWindow?

    static func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        else { return }
        let host = UIHostingController(rootView: ToastOverlay())
        host.view.backgroundColor = .clear
        let overlay = PassThroughWindow(windowScene: scene)
        overlay.rootViewController = host
        overlay.windowLevel = .alert + 1
        overlay.backgroundColor = .clear
        overlay.isHidden = false
        window = overlay
    }
}

/// Laesst Beruehrungen neben der Meldung zum Fenster darunter durch.
private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit === rootViewController?.view ? nil : hit
    }
}

private struct ToastOverlay: View {
    var body: some View {
        VStack {
            ToastView()
            Spacer()
        }
        .animation(.spring(duration: 0.3), value: Toast.shared.message)
        .tint(Ink.accent)
    }
}
