// Erzeugt die App-Icons (1024x1024 PNG) fuer die Asset-Kataloge.
//
// Warum ein Generator und keine abgelegte Datei: so ist nachvollziehbar,
// woraus ein Icon besteht, und eine Aenderung ist eine Zeile statt einer
// neuen Bilddatei aus einem Grafikprogramm.
//
//   swift tools/make-icon.swift <healthy|vault|fokus|einkaufsliste> <pfad/icon-1024.png>
//
// Vier Motive, vier Farbwelten - jede App soll auf dem Homebildschirm sofort
// als sie selbst zu erkennen sein:
//   healthy  ein Herz, gruen                          (Gesundheit)
//   vault    ein Vorhaengeschloss, dunkelblau         (Sicherheit)
//   fokus    ein Haken im orangenen Kreis auf Weiss  (erledigt, im Fokus)
//   einkaufsliste  eine Einkaufstasche mit Haken, petrol   (die Liste, abgehakt)
// Bewusst grob: bei 60 px auf dem Homebildschirm ueberlebt nur, was kraeftig
// ist. Keine Schrift, keine feinen Linien.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 2 else {
    fatalError("Aufruf: make-icon.swift <healthy|vault|fokus|einkaufsliste> <pfad/icon-1024.png>")
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
    // Herz: zwei Boegen oben, Spitze unten. Selbst gezeichnet, damit es
    // mittig sitzt und grob genug bleibt. Ohne Pulslinie - die ragte aus dem
    // Herz heraus und machte es unruhig; ein Herz allein sagt "Gesundheit"
    // deutlich genug.
    let w = side * 0.70, h = side * 0.62
    let cx = side / 2
    // Optische Mitte: die Boegen oben wiegen schwerer als die Spitze, deshalb
    // sitzt der Bezugspunkt ein wenig unter der Bildmitte.
    let cy = side * 0.50
    let heart = CGMutablePath()
    heart.move(to: CGPoint(x: cx, y: cy - h * 0.48))
    heart.addCurve(to: CGPoint(x: cx - w / 2, y: cy + h * 0.16),
                   control1: CGPoint(x: cx - w * 0.10, y: cy - h * 0.28),
                   control2: CGPoint(x: cx - w / 2, y: cy - h * 0.12))
    heart.addArc(center: CGPoint(x: cx - w / 4, y: cy + h * 0.16), radius: w / 4,
                 startAngle: .pi, endAngle: 0, clockwise: true)
    heart.addArc(center: CGPoint(x: cx + w / 4, y: cy + h * 0.16), radius: w / 4,
                 startAngle: .pi, endAngle: 0, clockwise: true)
    heart.addCurve(to: CGPoint(x: cx, y: cy - h * 0.48),
                   control1: CGPoint(x: cx + w / 2, y: cy - h * 0.12),
                   control2: CGPoint(x: cx + w * 0.10, y: cy - h * 0.28))
    heart.closeSubpath()
    withShadow {
        ctx.addPath(heart)
        ctx.setFillColor(ink)
        ctx.fillPath()
    }

case "vault":
    background(0x2B3A5C, 0x0B1020)
    // Vorhaengeschloss: Buegel als dicker Bogen, Koerper mit runden Ecken,
    // Schluesselloch in der Hintergrundfarbe.
    let cx = side / 2
    let bodyW = side * 0.50, bodyH = side * 0.40
    let shackleR = side * 0.17, shackleW = side * 0.075
    // Gesamthoehe des Schlosses (Koerper + Buegel) mittig ins Bild legen,
    // statt den Koerper an einer festen Kante abzusetzen.
    let total = bodyH + side * 0.02 + shackleR + shackleW / 2
    let bodyRect = CGRect(x: cx - bodyW / 2, y: (side - total) / 2, width: bodyW, height: bodyH)
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
    // Weisser Grund - Felix' Wunsch. Darauf ein orangener Kreis mit einem
    // kraeftigen Haken: erledigt, abgehakt, im Fokus. Orange ist die Farbe
    // der Flamme in der App, so gehoert das Icon erkennbar dazu.
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let c = CGPoint(x: side / 2, y: side / 2)
    let r = side * 0.36
    withShadow {
        let circle = CGGradient(colorsSpace: space,
                                colors: [rgb(0xFF9F3C), rgb(0xE5701A)] as CFArray,
                                locations: [0, 1])!
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.clip()
        ctx.drawLinearGradient(circle,
                               start: CGPoint(x: c.x - r, y: c.y + r),
                               end: CGPoint(x: c.x + r, y: c.y - r),
                               options: [])
        ctx.restoreGState()
    }
    let check = CGMutablePath()
    check.move(to: CGPoint(x: c.x - r * 0.46, y: c.y + r * 0.02))
    check.addLine(to: CGPoint(x: c.x - r * 0.12, y: c.y - r * 0.32))
    check.addLine(to: CGPoint(x: c.x + r * 0.50, y: c.y + r * 0.34))
    ctx.addPath(check)
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(side * 0.085)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

case "einkaufsliste":
    // Eine Einkaufstasche auf Petrol - eine Farbe, die keine der anderen
    // drei hat, damit sie auch neben Healthy auf demselben Homebildschirm
    // fuer sich steht. Auf der Tasche ein Haken: die Liste, abgehakt.
    background(0x1C9C9C, 0x0B4F55)
    let cx = side / 2
    let bodyW = side * 0.56, bodyH = side * 0.44
    let handleR = side * 0.16, handleW = side * 0.07
    // Henkel laeuft ein Stueck in die Tasche hinein; die Gesamthoehe aus
    // Koerper und sichtbarem Henkel liegt mittig im Bild.
    let overlap = side * 0.05
    let total = bodyH + handleR + handleW / 2 - overlap
    let bodyRect = CGRect(x: cx - bodyW / 2, y: (side - total) / 2, width: bodyW, height: bodyH)
    let handleY = bodyRect.maxY - overlap
    withShadow {
        let handle = CGMutablePath()
        handle.addArc(center: CGPoint(x: cx, y: handleY), radius: handleR,
                      startAngle: 0, endAngle: .pi, clockwise: false)
        ctx.addPath(handle)
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(handleW)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: side * 0.07,
                           cornerHeight: side * 0.07, transform: nil))
        ctx.setFillColor(ink)
        ctx.fillPath()
    }
    let c = CGPoint(x: bodyRect.midX, y: bodyRect.midY - side * 0.01)
    let r = bodyW * 0.40
    let check = CGMutablePath()
    check.move(to: CGPoint(x: c.x - r * 0.46, y: c.y + r * 0.02))
    check.addLine(to: CGPoint(x: c.x - r * 0.12, y: c.y - r * 0.32))
    check.addLine(to: CGPoint(x: c.x + r * 0.50, y: c.y + r * 0.34))
    ctx.addPath(check)
    ctx.setStrokeColor(rgb(0x0B4F55))
    ctx.setLineWidth(side * 0.065)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

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
