// Erzeugt die App-Icons (1024x1024 PNG) fuer die Asset-Kataloge.
//
// Warum ein Generator und keine abgelegte Datei: so ist nachvollziehbar,
// woraus ein Icon besteht, und eine Aenderung ist eine Zeile statt einer
// neuen Bilddatei aus einem Grafikprogramm.
//
//   swift tools/make-icon.swift <healthy|vault|fokus> <pfad/icon-1024.png>
//
// Drei Motive, drei Farbwelten - jede App soll auf dem Homebildschirm sofort
// als sie selbst zu erkennen sein:
//   healthy  ein Herz mit Pulslinie, gruen        (Gesundheit)
//   vault    ein Vorhaengeschloss, dunkelblau      (Sicherheit)
//   fokus    eine Zielscheibe mit Treffer, orange  (Fokus)
// Bewusst grob: bei 60 px auf dem Homebildschirm ueberlebt nur, was kraeftig
// ist. Keine Schrift, keine feinen Linien.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 2 else {
    fatalError("Aufruf: make-icon.swift <healthy|vault|fokus> <pfad/icon-1024.png>")
}
let variant = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

let size = 1024
let side = CGFloat(size)
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space,
            components: [CGFloat((hex >> 16) & 0xFF) / 255,
                         CGFloat((hex >> 8) & 0xFF) / 255,
                         CGFloat(hex & 0xFF) / 255, alpha])!
}

guard let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Kein Zeichenkontext")
}

/// Hintergrund als leichter Verlauf, damit die Flaeche nicht tot wirkt.
func background(_ first: UInt32, _ second: UInt32) {
    let gradient = CGGradient(colorsSpace: space,
                              colors: [rgb(first), rgb(second)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: side),
                           end: CGPoint(x: side, y: 0),
                           options: [])
}

/// Weicher Schatten unter dem Motiv, damit es sich vom Verlauf abhebt.
func withShadow(_ draw: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.02),
                  blur: side * 0.05, color: rgb(0x000000, 0.35))
    draw()
    ctx.restoreGState()
}

let ink = rgb(0xF4F7FB)

switch variant {

case "healthy":
    background(0x2E8B57, 0x0F3D24)
    // Herz: zwei Boegen oben, Spitze unten. Kein Klischee-Symbol aus einer
    // Schriftart, sondern selbst gezeichnet - so sitzt es mittig und grob.
    let cx = side / 2, cy = side * 0.56, w = side * 0.60, h = side * 0.54
    let heart = CGMutablePath()
    heart.move(to: CGPoint(x: cx, y: cy - h * 0.45))
    heart.addCurve(to: CGPoint(x: cx - w / 2, y: cy + h * 0.18),
                   control1: CGPoint(x: cx - w * 0.10, y: cy - h * 0.25),
                   control2: CGPoint(x: cx - w / 2, y: cy - h * 0.10))
    heart.addArc(center: CGPoint(x: cx - w / 4, y: cy + h * 0.18), radius: w / 4,
                 startAngle: .pi, endAngle: 0, clockwise: true)
    heart.addArc(center: CGPoint(x: cx + w / 4, y: cy + h * 0.18), radius: w / 4,
                 startAngle: .pi, endAngle: 0, clockwise: true)
    heart.addCurve(to: CGPoint(x: cx, y: cy - h * 0.45),
                   control1: CGPoint(x: cx + w / 2, y: cy - h * 0.10),
                   control2: CGPoint(x: cx + w * 0.10, y: cy - h * 0.25))
    heart.closeSubpath()
    withShadow {
        ctx.addPath(heart)
        ctx.setFillColor(ink)
        ctx.fillPath()
    }
    // Pulslinie quer durch das Herz, in der Hintergrundfarbe: der Schlag,
    // der aus einem Herz Gesundheit macht.
    let y = cy + h * 0.10
    let pulse = CGMutablePath()
    pulse.move(to: CGPoint(x: cx - w * 0.36, y: y))
    pulse.addLine(to: CGPoint(x: cx - w * 0.14, y: y))
    pulse.addLine(to: CGPoint(x: cx - w * 0.06, y: y + h * 0.22))
    pulse.addLine(to: CGPoint(x: cx + w * 0.04, y: y - h * 0.22))
    pulse.addLine(to: CGPoint(x: cx + w * 0.12, y: y))
    pulse.addLine(to: CGPoint(x: cx + w * 0.36, y: y))
    ctx.addPath(pulse)
    ctx.setStrokeColor(rgb(0x1F6B3F))
    ctx.setLineWidth(side * 0.045)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

case "vault":
    background(0x2B3A5C, 0x0B1020)
    // Vorhaengeschloss: Buegel als dicker Bogen, Koerper mit runden Ecken,
    // Schluesselloch in der Hintergrundfarbe.
    let cx = side / 2
    let bodyW = side * 0.50, bodyH = side * 0.40
    let bodyRect = CGRect(x: cx - bodyW / 2, y: side * 0.16, width: bodyW, height: bodyH)
    let shackleR = side * 0.17, shackleW = side * 0.075
    let shackleY = bodyRect.maxY + side * 0.02
    withShadow {
        let shackle = CGMutablePath()
        shackle.addArc(center: CGPoint(x: cx, y: shackleY), radius: shackleR,
                       startAngle: 0, endAngle: .pi, clockwise: false)
        ctx.addPath(shackle)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(shackleW)
        ctx.setLineCap(.butt)
        ctx.strokePath()
        // Die geraden Enden des Buegels, bis in den Koerper hinein.
        ctx.setFillColor(ink)
        ctx.fill(CGRect(x: cx - shackleR - shackleW / 2, y: bodyRect.maxY - side * 0.02,
                        width: shackleW, height: shackleY - bodyRect.maxY + side * 0.02))
        ctx.fill(CGRect(x: cx + shackleR - shackleW / 2, y: bodyRect.maxY - side * 0.02,
                        width: shackleW, height: shackleY - bodyRect.maxY + side * 0.02))
        ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: side * 0.07,
                           cornerHeight: side * 0.07, transform: nil))
        ctx.fillPath()
    }
    // Schluesselloch
    let holeR = side * 0.055
    let holeC = CGPoint(x: cx, y: bodyRect.midY + side * 0.03)
    ctx.setFillColor(rgb(0x1A2440))
    ctx.fillEllipse(in: CGRect(x: holeC.x - holeR, y: holeC.y - holeR,
                               width: holeR * 2, height: holeR * 2))
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: holeC.x - holeR * 0.45, y: holeC.y))
    slot.addLine(to: CGPoint(x: holeC.x - holeR * 0.75, y: holeC.y - side * 0.11))
    slot.addLine(to: CGPoint(x: holeC.x + holeR * 0.75, y: holeC.y - side * 0.11))
    slot.addLine(to: CGPoint(x: holeC.x + holeR * 0.45, y: holeC.y))
    slot.closeSubpath()
    ctx.addPath(slot)
    ctx.fillPath()

case "fokus":
    background(0xE8862A, 0x7A3A08)
    // Zielscheibe: drei Ringe, Treffer in der Mitte. Ringe als Striche,
    // damit der Hintergrund dazwischen durchscheint.
    let c = CGPoint(x: side / 2, y: side / 2)
    withShadow {
        ctx.setStrokeColor(ink)
        for (radius, width) in [(side * 0.36, side * 0.055), (side * 0.235, side * 0.05)] {
            ctx.setLineWidth(width)
            ctx.strokeEllipse(in: CGRect(x: c.x - radius, y: c.y - radius,
                                         width: radius * 2, height: radius * 2))
        }
        let dot = side * 0.10
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
    }

default:
    fatalError("Unbekannte App: \(variant)")
}

guard let image = ctx.makeImage() else { fatalError("Kein Bild") }
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Kein Ziel: \(outputPath)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Schreiben fehlgeschlagen") }
print("Geschrieben: \(outputPath)")
