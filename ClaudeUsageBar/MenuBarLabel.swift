import AppKit
import SwiftUI

/// Die Zeile in der Menüleiste als Bild: Strahlen-Zeichen und „45 %“.
///
/// Als Bild statt als HStack, aus demselben Grund wie in der AWSUsageBar:
/// `MenuBarExtra` zeigt von einem zusammengesetzten Label je nach macOS-Fassung
/// nur das Symbol. Ein Vorlagenbild (`isTemplate`) färbt macOS selbst.
@MainActor
enum MenuBarLabel {

    static func image(_ title: String, scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2) -> NSImage {
        let content = HStack(spacing: 4) {
            ClaudeMark(color: .black)
                .frame(width: 14, height: 14)
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
        image.accessibilityDescription = "Claude \(title)"
        return image
    }
}
