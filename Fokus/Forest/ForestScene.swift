import SceneKit
import SwiftUI

/// Der Wald als kleine Insel in 3D: jeder Baum eine Session, Groesse und Art
/// nach Dauer, gepflanzt in einer Spirale von innen nach aussen - der
/// aelteste in der Mitte, die Insel waechst mit. Eine Sonne mit Schatten,
/// Nebel in der Tiefe, die Kamera kreist langsam.
///
/// SceneKit, kein RealityKit: es laeuft im Simulator, braucht keine
/// USDZ-Dateien und ein paar hundert Knoten aus Kegeln und Kugeln reichen
/// fuer den Stil (siehe docs/ENTSCHEIDUNGEN.md). Die Szene wird bei jeder
/// Aenderung neu gebaut - billiger als Buchfuehrung ueber einzelne Knoten.
enum ForestScene {

    /// Abstand zweier Pflanzstellen in der Spirale.
    private static let spacing: Float = 1.25

    @MainActor
    static func build(sessions: [FocusSession], active: ActiveSession?, night: Bool) -> SCNScene {
        let scene = SCNScene()
        let palette = Palette(night: night)
        scene.background.contents = palette.skyImage()

        // Pflanzreihenfolge: aelteste zuerst, die steht in der Mitte.
        let planted = sessions.sorted { $0.start < $1.start }
        let count = planted.count + (active == nil ? 0 : 1)
        let radius = max(3.4, spacing * sqrt(Float(count) + 0.5) + 1.5)

        scene.rootNode.addChildNode(island(radius: radius, palette: palette))

        var spots: [SCNVector3] = []
        for (index, session) in planted.enumerated() {
            var rng = SeededRandom(seed: stableHash(session.id))
            let spot = spot(index, rng: &rng)
            spots.append(spot)
            let tree = tree(minutes: session.minutes, rng: &rng, palette: palette)
            tree.position = spot
            scene.rootNode.addChildNode(tree)
        }
        if let active {
            // Der wachsende Baum: von klein bis voll ueber die Restzeit -
            // eine Aktion, kein Neubau je Sekunde.
            var rng = SeededRandom(seed: stableHash(active.id))
            let spot = spot(planted.count, rng: &rng)
            spots.append(spot)
            let tree = tree(minutes: active.minutes, rng: &rng, palette: palette)
            let grower = SCNNode()
            grower.addChildNode(tree)
            grower.position = spot
            let start = 0.15 + 0.85 * Float(active.growth())
            grower.scale = SCNVector3(start, start, start)
            grower.runAction(.scale(to: 1, duration: max(0, active.end.timeIntervalSinceNow)))
            scene.rootNode.addChildNode(grower)
        }
        decorate(scene.rootNode, radius: radius, avoiding: spots, palette: palette)

        // Licht: eine Sonne mit weichem Schatten, dazu Grundhelligkeit.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = palette.sunIntensity
        sun.light?.color = palette.sunColor
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowRadius = 6
        sun.light?.shadowSampleCount = 16
        sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.32)
        sun.eulerAngles = SCNVector3(-1.05, 0.75, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = palette.ambientIntensity
        ambient.light?.color = palette.ambientColor
        scene.rootNode.addChildNode(ambient)

        // Kamera: schraeg von oben, weit genug weg fuer die ganze Insel,
        // und sie kreist - so ist die Tiefe zu sehen, ohne dass jemand dreht.
        let distance = radius * 2.2 + 3.5
        let orbit = SCNNode()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.camera?.zFar = 300
        camera.position = SCNVector3(0, distance * 0.6, distance)
        camera.look(at: SCNVector3(0, 0.3, 0))
        orbit.addChildNode(camera)
        orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 160)))
        scene.rootNode.addChildNode(orbit)

        scene.fogColor = palette.fog
        scene.fogStartDistance = CGFloat(distance * 0.9)
        scene.fogEndDistance = CGFloat(distance * 2.6)
        scene.fogDensityExponent = 1.6
        return scene
    }

    // MARK: - Insel

    private static func island(radius: Float, palette: Palette) -> SCNNode {
        let node = SCNNode()
        let grass = SCNCylinder(radius: CGFloat(radius), height: 0.5)
        grass.radialSegmentCount = 64
        grass.firstMaterial = material(palette.grass)
        let top = SCNNode(geometry: grass)
        top.position = SCNVector3(0, -0.25, 0)
        node.addChildNode(top)

        // Der Sockel: nach unten schmaler, wie eine schwebende Insel.
        let soil = SCNCone(topRadius: CGFloat(radius * 0.97), bottomRadius: CGFloat(radius * 0.45), height: 2.2)
        soil.radialSegmentCount = 64
        soil.firstMaterial = material(palette.soil)
        let base = SCNNode(geometry: soil)
        base.position = SCNVector3(0, -1.6, 0)
        node.addChildNode(base)
        return node
    }

    /// Blumen und Steine zwischen den Baeumen - nur Schmuck, aber der
    /// Unterschied zwischen einer Scheibe und einer Wiese.
    private static func decorate(_ root: SCNNode, radius: Float, avoiding spots: [SCNVector3], palette: Palette) {
        var rng = SeededRandom(seed: 0x5EED_F0E5_7)
        let flowerColors = palette.flowers
        let stone = material(palette.stone)
        for index in 0..<Int(radius * 7) {
            let r = rng.next(in: 0.4...(radius - 0.5))
            let a = rng.next(in: 0..<(2 * Float.pi))
            let position = SCNVector3(r * cos(a), 0, r * sin(a))
            let tooClose = spots.contains { hypot($0.x - position.x, $0.z - position.z) < 0.55 }
            if tooClose { continue }
            let node: SCNNode
            if index % 4 == 0 {
                let geometry = SCNSphere(radius: 0.13)
                geometry.firstMaterial = stone
                node = SCNNode(geometry: geometry)
                node.scale = SCNVector3(1.3, 0.5, 1)
            } else {
                let geometry = SCNSphere(radius: 0.065)
                geometry.firstMaterial = material(flowerColors[index % flowerColors.count])
                node = SCNNode(geometry: geometry)
                node.position.y = 0.08
            }
            node.position.x = position.x
            node.position.z = position.z
            root.addChildNode(node)
        }
    }

    // MARK: - Baeume

    /// Pflanzstelle Nummer `index` in einer Sonnenblumen-Spirale (137,5 Grad
    /// je Schritt): fuellt die Scheibe gleichmaessig, egal wie viele es sind.
    private static func spot(_ index: Int, rng: inout SeededRandom) -> SCNVector3 {
        let golden: Float = 2.399963
        let r = spacing * sqrt(Float(index) + 0.5)
        let a = Float(index) * golden
        let jitter = spacing * 0.16
        return SCNVector3(r * cos(a) + rng.next(in: -jitter...jitter), 0,
                          r * sin(a) + rng.next(in: -jitter...jitter))
    }

    /// Vier Arten nach Dauer: Setzling, junge Tanne, ausgewachsene Tanne,
    /// alter Laubbaum. Jeder ein bisschen anders in Groesse, Drehung und
    /// Gruenton - aus der Session-Id, damit er bei jedem Bild derselbe ist.
    private static func tree(minutes: Int, rng: inout SeededRandom, palette: Palette) -> SCNNode {
        let node = SCNNode()
        let crown = material(palette.crown(shift: rng.next(in: -0.05...0.05)))
        let bark = material(palette.trunk)
        switch TreeSize(minutes: minutes) {
        case .sapling:
            node.addChildNode(trunk(height: 0.35, radius: 0.05, bark))
            node.addChildNode(ball(radius: 0.28, y: 0.55, crown))
        case .young:
            node.addChildNode(trunk(height: 0.5, radius: 0.07, bark))
            node.addChildNode(cone(bottom: 0.55, height: 0.7, y: 0.5, crown))
            node.addChildNode(cone(bottom: 0.4, height: 0.55, y: 0.95, crown))
        case .grown:
            node.addChildNode(trunk(height: 0.7, radius: 0.1, bark))
            node.addChildNode(cone(bottom: 0.75, height: 0.8, y: 0.7, crown))
            node.addChildNode(cone(bottom: 0.58, height: 0.7, y: 1.2, crown))
            node.addChildNode(cone(bottom: 0.4, height: 0.6, y: 1.7, crown))
        case .old:
            node.addChildNode(trunk(height: 1.0, radius: 0.14, bark))
            node.addChildNode(ball(radius: 0.8, y: 1.5, crown))
            node.addChildNode(ball(radius: 0.55, y: 1.9, crown, x: 0.45))
            node.addChildNode(ball(radius: 0.5, y: 1.85, crown, x: -0.4, z: 0.3))
            node.addChildNode(ball(radius: 0.5, y: 2.15, crown, z: -0.25))
        }
        let scale = rng.next(in: 0.9...1.1)
        node.scale = SCNVector3(scale, scale, scale)
        node.eulerAngles.y = rng.next(in: 0..<(2 * Float.pi))
        // Ein Knoten je Baum statt vier: weniger Zeichenaufrufe bei einem
        // Jahr voller Baeume.
        return node.flattenedClone()
    }

    private static func trunk(height: Float, radius: Float, _ material: SCNMaterial) -> SCNNode {
        let geometry = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
        geometry.radialSegmentCount = 12
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(0, height / 2, 0)
        return node
    }

    private static func cone(bottom: Float, height: Float, y: Float, _ material: SCNMaterial) -> SCNNode {
        let geometry = SCNCone(topRadius: 0, bottomRadius: CGFloat(bottom), height: CGFloat(height))
        geometry.radialSegmentCount = 14
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(0, y + height / 2, 0)
        return node
    }

    private static func ball(radius: Float, y: Float, _ material: SCNMaterial,
                             x: Float = 0, z: Float = 0) -> SCNNode {
        let geometry = SCNSphere(radius: CGFloat(radius))
        geometry.segmentCount = 18
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(x, y, z)
        return node
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        return material
    }

    // MARK: - Farben

    struct Palette {
        let night: Bool

        var grass: UIColor { night ? UIColor(red: 0.20, green: 0.40, blue: 0.24, alpha: 1)
                                   : UIColor(red: 0.47, green: 0.74, blue: 0.36, alpha: 1) }
        var soil: UIColor { night ? UIColor(red: 0.24, green: 0.18, blue: 0.14, alpha: 1)
                                  : UIColor(red: 0.47, green: 0.34, blue: 0.24, alpha: 1) }
        var trunk: UIColor { night ? UIColor(red: 0.28, green: 0.20, blue: 0.14, alpha: 1)
                                   : UIColor(red: 0.45, green: 0.30, blue: 0.19, alpha: 1) }
        var stone: UIColor { night ? UIColor(white: 0.35, alpha: 1) : UIColor(white: 0.62, alpha: 1) }
        var flowers: [UIColor] {
            night ? [UIColor(white: 0.7, alpha: 1), UIColor(red: 0.75, green: 0.7, blue: 0.5, alpha: 1)]
                  : [UIColor(white: 0.98, alpha: 1), UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1),
                     UIColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 1)]
        }
        var skyTop: UIColor { night ? UIColor(red: 0.05, green: 0.07, blue: 0.17, alpha: 1)
                                    : UIColor(red: 0.55, green: 0.78, blue: 0.93, alpha: 1) }
        var skyBottom: UIColor { night ? UIColor(red: 0.13, green: 0.17, blue: 0.30, alpha: 1)
                                       : UIColor(red: 0.90, green: 0.95, blue: 0.98, alpha: 1) }
        var fog: UIColor { skyBottom }
        var sunIntensity: CGFloat { night ? 450 : 1100 }
        var sunColor: UIColor { night ? UIColor(red: 0.75, green: 0.82, blue: 1.0, alpha: 1)
                                      : UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1) }
        var ambientIntensity: CGFloat { night ? 260 : 420 }
        var ambientColor: UIColor { night ? UIColor(red: 0.6, green: 0.7, blue: 1.0, alpha: 1) : .white }

        /// Kronen: ein Grund-Gruen, je Baum leicht verschoben.
        func crown(shift: Float) -> UIColor {
            let base: (h: CGFloat, s: CGFloat, b: CGFloat) = night ? (0.36, 0.55, 0.42) : (0.33, 0.62, 0.62)
            return UIColor(hue: base.h + CGFloat(shift), saturation: base.s,
                           brightness: base.b + CGFloat(shift) * 0.8, alpha: 1)
        }

        /// Der Himmel als Verlauf - SceneKit nimmt fuer den Hintergrund ein
        /// Bild, ein Farbverlauf direkt geht nicht.
        func skyImage() -> UIImage {
            let size = CGSize(width: 8, height: 256)
            return UIGraphicsImageRenderer(size: size).image { context in
                let colors = [skyTop.cgColor, skyBottom.cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: colors, locations: [0, 1]) else { return }
                context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                     end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    // MARK: - Zufall mit Gedaechtnis

    /// FNV-1a: `hashValue` ist je Prozess anders gesalzen, der Wald saehe
    /// nach jedem Start anders aus.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// SplitMix64 - klein, schnell, und dieselbe Saat liefert dieselbe Folge.
    struct SeededRandom {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func nextRaw() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func next(in range: ClosedRange<Float>) -> Float {
            let unit = Float(nextRaw() >> 40) / Float(1 << 24)
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }

        mutating func next(in range: Range<Float>) -> Float {
            let unit = Float(nextRaw() >> 40) / Float(1 << 24)
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }
    }
}

/// Die Szene in SwiftUI. Neu gebaut, wenn sich Baeume, laufende Session oder
/// Hell/Dunkel aendern - der wachsende Baum waechst dazwischen als Aktion.
struct ForestSceneView: View {

    let sessions: [FocusSession]
    let active: ActiveSession?

    @Environment(\.colorScheme) private var colorScheme
    @State private var scene: SCNScene?

    private struct Key: Equatable {
        let ids: [String]
        let activeID: String?
        let night: Bool
    }

    private var key: Key {
        Key(ids: sessions.map(\.id), activeID: active?.id, night: colorScheme == .dark)
    }

    var body: some View {
        SceneView(scene: scene,
                  options: [.rendersContinuously],
                  preferredFramesPerSecond: 30,
                  antialiasingMode: .multisampling4X)
            .task(id: key) {
                scene = ForestScene.build(sessions: sessions, active: active, night: colorScheme == .dark)
            }
    }
}
