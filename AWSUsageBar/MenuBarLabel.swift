import AppKit
import SwiftUI

/// Die Zeile in der Menüleiste als Bild: Wolke und „38 % · 19,01 $“.
///
/// Als Bild statt als HStack aus Image und Text: `MenuBarExtra` zeigt von einem
/// zusammengesetzten Label je nach macOS-Fassung nur das Symbol. Ein
/// Vorlagenbild (`isTemplate`) färbt macOS selbst - hell, dunkel, hervorgehoben.
@MainActor
enum MenuBarLabel {

    static func image(_ title: String, scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2) -> NSImage {
        let content = HStack(spacing: 4) {
            Image(systemName: "cloud")
                .font(.system(size: 13, weight: .medium))
            Text(title)
                .font(.system(size: 13).monospacedDigit())
        }
        .foregroundStyle(.black)
        .fixedSize()
        .padding(.vertical, 1)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return NSImage() }
        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: CGFloat(cgImage.width) / scale,
                                         height: CGFloat(cgImage.height) / scale))
        image.isTemplate = true
        image.accessibilityDescription = "AWS \(title)"
        return image
    }
}
