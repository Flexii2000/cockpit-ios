import SwiftUI
import UIKit

/// Eine kurze Meldung oben, ueber allem - vor allem, wenn eine Aenderung, die
/// schon zu sehen war, beim Dienst nicht durchging und zurueckgedreht wurde.
///
/// In einem eigenen Fenster, nicht im Inhalt: die Ablehnung kommt oft spaeter,
/// waehrend ein Blatt offen ist oder man im anderen Tab ist - dort waere eine
/// Leiste im Inhalt unsichtbar. Muster wie `ToastWindow` in coHabit.
@MainActor
@Observable
final class NoticeCenter {

    static let shared = NoticeCenter()

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let text: String
        /// Grau statt rot: das Ziel war schlicht nicht mehr da.
        let isInfo: Bool
    }

    private(set) var current: Notice?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String, isInfo: Bool = false) {
        let notice = Notice(text: text, isInfo: isInfo)
        current = notice
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isInfo ? 4 : 6))
            guard !Task.isCancelled, self?.current?.id == notice.id else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        hideTask?.cancel()
        current = nil
    }
}

/// Das Fenster fuer die Meldung - ueber allen Blaettern, laesst jede Beruehrung
/// durch, die nicht die Meldung trifft.
@MainActor
enum NoticeWindow {

    private static var window: UIWindow?

    static func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        else { return }
        let host = UIHostingController(rootView: NoticeOverlay())
        host.view.backgroundColor = .clear
        let overlay = NoticePassThroughWindow(windowScene: scene)
        overlay.rootViewController = host
        overlay.windowLevel = .alert + 1
        overlay.backgroundColor = .clear
        overlay.isHidden = false
        window = overlay
    }
}

private final class NoticePassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit === rootViewController?.view ? nil : hit
    }
}

private struct NoticeOverlay: View {
    private var center: NoticeCenter { NoticeCenter.shared }

    var body: some View {
        VStack {
            if let notice = center.current {
                Text(notice.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(notice.isInfo ? Color.primary : Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(notice.isInfo ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.red.gradient),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .onTapGesture { center.dismiss() }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("notice")
            }
            Spacer()
        }
        .animation(.spring(duration: 0.3), value: center.current)
    }
}
