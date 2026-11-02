#if DEBUG
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Bilder des Ausklappfensters für die Prüfung ohne Klick in die Menüleiste
/// (`CLAUDE_USAGE_SNAPSHOT`, siehe `ClaudeUsageBarApp`). Erfundene Zahlen - das
/// Repo ist öffentlich, und claude.ai wird dafür nicht gefragt.
///
/// `ImageRenderer` zeichnet weder Liquid Glass noch AppKit-Menüs: die Karten
/// stehen flach da (`flatGlass`), das Menü als gelber Platzhalter, der Rest ist echt.
@MainActor
enum Snapshot {

    static let now = Date()

    static func model() -> UsageModel {
        let start = now.addingTimeInterval(-4.6 * 86_400)
        let reset = start.addingTimeInterval(7 * 86_400)
        let usage = ClaudeUsage(
            weekly: .init(id: "weekly_all", title: "Alle Modelle", percent: 62, resetsAt: reset),
            scoped: [.init(id: "weekly_scoped-1-Fable", title: "Fable", percent: 18, resetsAt: reset)],
            session: nil,
            breakdown: [
                .init(key: "claude_code", title: "Claude Code", percent: 71),
                .init(key: "chat", title: "Chats", percent: 24),
                .init(key: "cowork", title: "Cowork", percent: 5),
                .init(key: "other", title: "Sonstige", percent: 0),
            ],
            weekStartedAt: start,
            extra: nil)
        return UsageModel(preview: usage, at: now)
    }

    static func write(model: UsageModel, to requested: URL) {
        // Die App läuft in der Sandbox und darf nur in ihren Container schreiben -
        // ein Ordner außerhalb geht still verloren. Dann in den Temp-Ordner des
        // Containers; die Pfade stehen in der Ausgabe.
        var folder = requested
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            folder = FileManager.default.temporaryDirectory.appending(path: "snapshot")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let signedOut = UsageModel(preview: nil, at: now)
        for (name, shown) in [("", model), ("-signed-out", signedOut)] {
            for scheme in [ColorScheme.light, .dark] {
                let background = scheme == .dark ? Color(white: 0.17) : Color(white: 0.95)
                let view = PopoverView(model: shown)
                    .background(background)
                    .environment(\.colorScheme, scheme)
                    .environment(\.flatGlass, true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let file = "claudeusagebar\(name)-\(scheme == .dark ? "dark" : "light").png"
                if let image = renderer.cgImage {
                    write(image, to: folder.appending(path: file))
                }
            }
        }
        // Die Menüleisten-Zeile - schwarz auf durchsichtig, fürs Bild auf Weiß.
        let title = ClaudeUsageFormat.menuBarTitle(model.usage)
        let label = MenuBarLabel.image(title, scale: 2)
        if let cgImage = label.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let renderer = ImageRenderer(content: Image(decorative: cgImage, scale: 2)
                .padding(6)
                .background(Color.white))
            renderer.scale = 2
            if let image = renderer.cgImage {
                write(image, to: folder.appending(path: "claudeusagebar-menubar.png"))
            }
        }
        print("Menueleiste: \(title)")
        NSApplication.shared.terminate(nil)
    }

    /// Fragt ohne Sitzung - claude.ai muss mit 401 antworten (`signedOut`), nicht
    /// mit einer Cloudflare-Seite (`challenged`).
    static func probe(_ web: ClaudeWeb) async {
        do {
            let data = try await web.get("/api/organizations")
            print("Probe: 2xx, \(data.count) Bytes")
        } catch {
            print("Probe: \(error)")
        }
        // Schlüsselbund aus der Sandbox: ein Schein-Cookie unter eigenem Konto
        // schreiben, lesen, löschen - die echte Sitzung bleibt unberührt.
        let fake = HTTPCookie(properties: [.name: "probe", .value: "x", .domain: ".claude.ai", .path: "/"])!
        let account = "probe"
        let saved = await Task.detached { SessionKeychain.save([.init(fake)], account: account) }.value
        let loaded = await Task.detached { SessionKeychain.load(account: account) }.value
        await Task.detached { SessionKeychain.delete(account: account) }.value
        let gone = await Task.detached { SessionKeychain.load(account: account) }.value == nil
        print("Schluesselbund: geschrieben \(saved), gelesen \(loaded?.first?.name ?? "-"), geloescht \(gone)")
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
