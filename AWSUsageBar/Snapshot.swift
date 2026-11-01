#if DEBUG
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Bilder des Ausklappfensters fuer die Pruefung ohne Klick in die Menueleiste
/// (`COCKPIT_AWS_SNAPSHOT`, siehe `AWSUsageBarApp`). Mit `COCKPIT_URL_AWS` gegen
/// einen Schein-Server und `COCKPIT_FH_PRIVATE_TOKEN` ohne Schluesselbund.
///
/// `ImageRenderer` zeichnet keine AppKit-Steuerelemente (Schalter, Knoepfe mit
/// Rahmen) - die fehlen auf dem Bild, der Rest ist echt.
@MainActor
enum Snapshot {

    static func write(model: UsageModel, to folder: URL) async {
        await model.refresh()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let background = scheme == .dark ? Color(white: 0.17) : Color(white: 0.95)
            let view = PopoverView(model: model)
                .background(background)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let name = "awsusagebar-\(scheme == .dark ? "dark" : "light").png"
            if let image = renderer.cgImage {
                write(image, to: folder.appending(path: name))
            }
        }
        // Die Menueleisten-Zeile - sie ist das, was den ganzen Tag sichtbar ist. Das
        // Vorlagenbild ist schwarz auf durchsichtig; fuers Bild auf Weiss gelegt.
        let title = AWSUsageFormat.menuBarTitle(model.usage)
        let label = MenuBarLabel.image(title, scale: 2)
        if let cgImage = label.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let renderer = ImageRenderer(content: Image(decorative: cgImage, scale: 2)
                .padding(6)
                .background(Color.white))
            renderer.scale = 2
            if let image = renderer.cgImage {
                write(image, to: folder.appending(path: "awsusagebar-menubar.png"))
            }
        }
        print("Menueleiste: \(title)")
        NSApplication.shared.terminate(nil)
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print(url.path)
    }
}
#endif
