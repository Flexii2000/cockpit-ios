import SwiftUI

/// Die AWS-Kosten in der Menüleiste - „☁ 38 % · 19,01 $“, darunter das
/// Ausklappfenster. Dieselben Zahlen wie der AWS-Tab in Vault (Dienst `aws-usage`).
/// Keine Mitteilungen: die Budget-Pushes gehen nur aufs iPhone (Felix, 01.11.).
@main
struct AWSUsageBarApp: App {

    @State private var model: UsageModel

    init() {
        let model = UsageModel()
        _model = State(initialValue: model)
        #if DEBUG
        // COCKPIT_AWS_SNAPSHOT=<Ordner>: Ausklappfenster hell und dunkel als Bild
        // ablegen und beenden - ein Fenster der Menüleiste laesst sich aus dem
        // Terminal nicht oeffnen, und screencapture darf dort nicht aufnehmen.
        if let folder = ProcessInfo.processInfo.environment["COCKPIT_AWS_SNAPSHOT"], !folder.isEmpty {
            Task { @MainActor in await Snapshot.write(model: model, to: URL(fileURLWithPath: folder)) }
            return
        }
        #endif
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(nsImage: MenuBarLabel.image(AWSUsageFormat.menuBarTitle(model.usage)))
        }
        .menuBarExtraStyle(.window)
    }
}
