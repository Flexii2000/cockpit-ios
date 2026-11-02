import SwiftUI

/// Die Claude-Nutzung in der Menüleiste - „45 %“ der Woche, darunter das
/// Ausklappfenster. Ersatz für die Claude Usage Bar (Felix, 02.11.): statt einen
/// kopierten Sitzungs-Cookie einzufügen, meldet man sich im eigenen Fenster bei
/// claude.ai an, und die Sitzung liegt nur im Schlüsselbund.
@main
struct ClaudeUsageBarApp: App {

    @State private var model: UsageModel

    init() {
        #if DEBUG
        // CLAUDE_USAGE_SNAPSHOT=<Ordner>: Ausklappfenster hell und dunkel als Bild
        // ablegen und beenden - mit erfundenen Zahlen, ohne claude.ai und ohne
        // Schlüsselbund. Ein Fenster der Menüleiste lässt sich aus dem Terminal
        // nicht öffnen.
        if let folder = ProcessInfo.processInfo.environment["CLAUDE_USAGE_SNAPSHOT"], !folder.isEmpty {
            let model = Snapshot.model()
            _model = State(initialValue: model)
            Task { @MainActor in Snapshot.write(model: model, to: URL(fileURLWithPath: folder)) }
            return
        }
        // CLAUDE_USAGE_PROBE=1: einmal ohne Sitzung bei claude.ai fragen und das
        // Ergebnis ausgeben - prüft WebKit und Cloudflare, ohne Anmeldung.
        if ProcessInfo.processInfo.environment["CLAUDE_USAGE_PROBE"] == "1" {
            let model = UsageModel()
            _model = State(initialValue: model)
            Task { @MainActor in await Snapshot.probe(model.web) }
            return
        }
        #endif
        let model = UsageModel()
        _model = State(initialValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(nsImage: MenuBarLabel.image(menuBarTitle))
        }
        .menuBarExtraStyle(.window)

        Window("Bei Claude anmelden", id: LoginView.windowID) {
            LoginView(model: model)
        }
        .defaultSize(width: 480, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }

    private var menuBarTitle: String {
        model.phase == .signedOut ? "–" : ClaudeUsageFormat.menuBarTitle(model.usage)
    }
}
