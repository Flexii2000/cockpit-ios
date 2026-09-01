// Erzeugt das App-Icon (1024x1024 PNG) fuer Assets.xcassets.
//
// Warum ein Generator und keine abgelegte Datei: so ist nachvollziehbar,
// woraus das Icon besteht, und eine Farbaenderung ist eine Zeile statt einer
// neuen Bilddatei aus einem Grafikprogramm.
//
//   swift tools/make-icon.swift Cockpit/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// Motiv: ein Instrument, wie man es in einem Cockpit erwartet. Der Bogen ist
// in drei Abschnitte geteilt - einer je Dienst, in den Farben, die der
// Kalorienzaehler schon fuer seine Tachos benutzt. Bewusst grob: bei 60 px auf
// dem Homebildschirm ueberlebt nur, was kraeftig ist.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "icon-1024.png"

let size = 1024
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

let side = CGFloat(size)

// Hintergrund: der Farbton, den die Weboberflaechen schon benutzen (#0f1420),
// als leichter Verlauf, damit die Flaeche nicht tot wirkt.
let background = CGGradient(colorsSpace: space,
                            colors: [rgb(0x1B2334), rgb(0x0B0F19)] as CFArray,
                            locations: [0, 1])!
ctx.drawLinearGradient(background,
                       start: CGPoint(x: 0, y: side),
                       end: CGPoint(x: side, y: 0),
                       options: [])

let center = CGPoint(x: side / 2, y: side * 0.44)
let radius = side * 0.30
let thickness = side * 0.115

func deg(_ value: CGFloat) -> CGFloat { value * .pi / 180 }

/// Ein Abschnitt des Bogens, mit Verlauf innerhalb des Abschnitts.
func arcSegment(from start: CGFloat, to end: CGFloat, _ first: UInt32, _ second: UInt32) {
    ctx.saveGState()
    let path = CGMutablePath()
    path.addArc(center: center, radius: radius,
                startAngle: deg(start), endAngle: deg(end), clockwise: true)
    ctx.addPath(path)
    ctx.setLineWidth(thickness)
    ctx.setLineCap(.butt)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [rgb(first), rgb(second)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: center.x - radius, y: center.y + radius),
                           end: CGPoint(x: center.x + radius, y: center.y - radius),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// Die drei Verlaeufe stammen aus food/src/main/resources/static/index.html -
// dieselben Toene wie in den Tachos des Kalorienzaehlers.
let gap: CGFloat = 4
arcSegment(from: 210, to: 130 + gap, 0x8BA3FF, 0x4C6EF5)   // Essen
arcSegment(from: 130, to: 50 + gap, 0x8EE09B, 0x43A75A)    // Gewicht
arcSegment(from: 50, to: -30, 0xFFD68A, 0xF59F26)          // Finanzen

// Zeiger: zeigt in den gruenen Abschnitt, also dorthin, wo alles im Rahmen
// liegt. Als schlankes Dreieck, damit er auch klein noch als Zeiger lesbar ist.
let needleAngle = deg(96)
let needleLength = radius * 0.86
let needleWidth = side * 0.030

let tip = CGPoint(x: center.x + cos(needleAngle) * needleLength,
                  y: center.y + sin(needleAngle) * needleLength)
let left = CGPoint(x: center.x + cos(needleAngle + .pi / 2) * needleWidth,
                   y: center.y + sin(needleAngle + .pi / 2) * needleWidth)
let right = CGPoint(x: center.x + cos(needleAngle - .pi / 2) * needleWidth,
                    y: center.y + sin(needleAngle - .pi / 2) * needleWidth)

let needle = CGMutablePath()
needle.move(to: tip)
needle.addLine(to: left)
needle.addLine(to: right)
needle.closeSubpath()
ctx.addPath(needle)
ctx.setFillColor(rgb(0xE6ECF5))
ctx.fillPath()

// Nabe: der dunkle Punkt darunter setzt den Zeiger ab, sonst wirkt er
// angeklebt.
ctx.setFillColor(rgb(0xE6ECF5))
ctx.fillEllipse(in: CGRect(x: center.x - side * 0.052, y: center.y - side * 0.052,
                           width: side * 0.104, height: side * 0.104))
ctx.setFillColor(rgb(0x121828))
ctx.fillEllipse(in: CGRect(x: center.x - side * 0.026, y: center.y - side * 0.026,
                           width: side * 0.052, height: side * 0.052))

guard let image = ctx.makeImage() else { fatalError("Kein Bild") }
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Kein Ziel: \(outputPath)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Schreiben fehlgeschlagen") }
print("Geschrieben: \(outputPath)")
