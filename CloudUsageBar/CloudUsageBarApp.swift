import SwiftUI

/// Die Cloud-Kosten in der Menüleiste - „☁ 38 % · 19,01 $ · 3,20 €“ (AWS, dahinter
/// Verda), darunter das Ausklappfenster. Dieselben Zahlen wie der Cloud-Tab in Vault
/// (Dienst `cloud-usage`; bis 02.11. hieß die App AWSUsageBar). Die Budget-Pushes
/// gehen nur aufs iPhone (Felix, 01.11.), auch die von Verda; die einzige
/// Mac-Mitteilung ist „Spot frei“, während das LLM auf On-Demand läuft (02.11.).
@main
struct CloudUsageBarApp: App {

    @State private var model: UsageModel

    init() {
        let model = UsageModel()
        _model = State(initialValue: model)
        #if DEBUG
        // COCKPIT_CLOUD_SNAPSHOT=<Ordner>: Ausklappfenster hell und dunkel als Bild
        // ablegen und beenden - ein Fenster der Menüleiste laesst sich aus dem
        // Terminal nicht oeffnen, und screencapture darf dort nicht aufnehmen.
        if let folder = ProcessInfo.processInfo.environment["COCKPIT_CLOUD_SNAPSHOT"], !folder.isEmpty {
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
            Image(nsImage: MenuBarLabel.image(CloudUsageFormat.menuBarTitle(model.usage)))
        }
        .menuBarExtraStyle(.window)
    }
}
