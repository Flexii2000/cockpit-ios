import SceneKit
import SwiftUI

/// Der Wald als kleine Insel in 3D: jeder Baum eine Session, Groesse nach
/// Dauer, Art nach Zufall der Session-Id - Tannen, Eichen, Birken,
/// Bluetenbaeume, Herbstbaeume, Zypressen. Dazwischen eine Wiese mit
/// Grasflecken, Blumen, Bueschen, Pilzen und Steinen, ein Teich mit
/// Seerosen, am Tag Schmetterlinge und Wolken, nachts Sterne, Mond und
/// Gluehwuermchen. Eine Sonne mit Schatten, Nebel in der Tiefe, die Kamera
/// kreist langsam.
///
/// SceneKit, kein RealityKit: es laeuft im Simulator, braucht keine
/// USDZ-Dateien, und ein paar hundert Knoten aus Kegeln und Kugeln reichen
/// fuer den Stil (siehe docs/ENTSCHEIDUNGEN.md). Die Szene wird bei jeder
/// Aenderung neu gebaut - billiger als Buchfuehrung ueber einzelne Knoten.
enum ForestScene {

    /// Abstand zweier Pflanzstellen in der Spirale.
    private static let spacing: Float = 1.3

    @MainActor
    static func build(sessions: [FocusSession], active: ActiveSession?, sun: Daylight.Sun) -> SCNScene {
        let scene = SCNScene()
        let palette = Palette(phase: sun.phase)
        scene.background.contents = palette.skyImage(sun: sun)
        let root = scene.rootNode

        // Pflanzreihenfolge: aelteste zuerst, die steht in der Mitte.
        let planted = sessions.sorted { $0.start < $1.start }
        let count = planted.count + (active == nil ? 0 : 1)
        let radius = max(3.8, spacing * sqrt(Float(count) + 0.5) + 1.9)
        root.addChildNode(island(radius: radius, palette: palette))

        var spots: [SCNVector3] = []
        for (index, session) in planted.enumerated() {
            var rng = SeededRandom(seed: stableHash(session.id))
            let spot = spot(index, rng: &rng)
            spots.append(spot)
            let tree = tree(minutes: session.minutes, rng: &rng, palette: palette)
            tree.position = spot
            root.addChildNode(tree)
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
            root.addChildNode(grower)
        }

        // Der Schmuck waechst mit den Baeumen: je mehr gepflanzt ist, desto
        // mehr Blumen, Pilze, Falter und Wolken - eine junge Insel darf
        // leer aussehen, die Schoenheit ist verdient (Felix, 2026-09-22).
        var rng = SeededRandom(seed: 0x5EED_F0E5_7 &+ UInt64(count))
        decorate(root, radius: radius, trees: count, avoiding: spots, palette: palette, rng: &rng)
        animateSky(root, radius: radius, trees: count, palette: palette, rng: &rng)

        // Licht: die Sonne (nachts der Mond) mit weichem Schatten, dazu
        // Grundhelligkeit. Sie steht, wo sie ueber Hamburg gerade steht -
        // morgens im Osten, abends flach im Westen, die Schatten wandern mit.
        // Die Schattenprojektion ist fest auf die Insel gelegt: passt sie sich
        // der Kamera an, wandern die Schattenkanten bei jeder Drehung und die
        // Wiese flackert.
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .directional
        light.light?.intensity = palette.sunIntensity
        light.light?.color = palette.sunColor
        light.light?.castsShadow = true
        light.light?.shadowMode = .deferred
        light.light?.shadowRadius = 5
        light.light?.shadowSampleCount = 12
        light.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.light?.shadowColor = UIColor.black.withAlphaComponent(palette.night ? 0.45 : 0.3)
        light.light?.automaticallyAdjustsShadowProjection = false
        light.light?.orthographicScale = Double(radius) * 1.15
        light.light?.zNear = 1
        light.light?.zFar = Double(radius) * 6
        let elevation = palette.night ? 0.9 : Float(max(0.28, min(1.2, sun.elevation)))
        light.eulerAngles = SCNVector3(-elevation, Float(sun.azimuth) + .pi, 0)
        // Der Lichtknoten steht hoch ueber der Insel, damit die feste
        // Projektion alles erfasst.
        light.position = SCNVector3(0, radius * 3, 0)
        root.addChildNode(light)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = palette.ambientIntensity
        ambient.light?.color = palette.ambientColor
        root.addChildNode(ambient)

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
        root.addChildNode(orbit)

        scene.fogColor = palette.fog
        scene.fogStartDistance = CGFloat(distance * 0.95)
        scene.fogEndDistance = CGFloat(distance * 2.8)
        scene.fogDensityExponent = 1.6
        return scene
    }

    // MARK: - Insel

    private static func island(radius: Float, palette: Palette) -> SCNNode {
        let node = SCNNode()
        let grass = SCNCylinder(radius: CGFloat(radius), height: 0.5)
        grass.radialSegmentCount = 72
        grass.firstMaterial = material(palette.grass)
        let top = SCNNode(geometry: grass)
        top.position = SCNVector3(0, -0.25, 0)
        node.addChildNode(top)

        // Der Sockel: nach unten schmaler, wie eine schwebende Insel, mit
        // einer helleren Erdkante direkt unter dem Rasen.
        let rim = SCNCylinder(radius: CGFloat(radius * 0.995), height: 0.18)
        rim.radialSegmentCount = 72
        rim.firstMaterial = material(palette.soilLight)
        let edge = SCNNode(geometry: rim)
        edge.position = SCNVector3(0, -0.58, 0)
        node.addChildNode(edge)

        let soil = SCNCone(topRadius: CGFloat(radius * 0.97), bottomRadius: CGFloat(radius * 0.4), height: 2.4)
        soil.radialSegmentCount = 72
        soil.firstMaterial = material(palette.soil)
        let base = SCNNode(geometry: soil)
        base.position = SCNVector3(0, -1.85, 0)
        node.addChildNode(base)
        return node
    }

    // MARK: - Wiese

    /// Alles, was keine Baeume sind: Grasflecken, Blumen, Pilze, Steine und
    /// der Teich. Haelt Abstand zu den Staemmen. Buesche gibt es hier nicht -
    /// die werden gepflanzt wie Baeume.
    private static func decorate(_ root: SCNNode, radius: Float, trees: Int, avoiding spots: [SCNVector3],
                                 palette: Palette, rng: inout SeededRandom) {
        func free(_ x: Float, _ z: Float, _ margin: Float) -> Bool {
            !spots.contains { hypot($0.x - x, $0.z - z) < margin }
        }
        func place(_ margin: Float, rng: inout SeededRandom, edge: Float = 0.5) -> SCNVector3? {
            for _ in 0..<6 {
                let r = rng.next(in: 0.3...(radius - edge))
                let a = rng.next(in: 0..<(2 * Float.pi))
                let x = r * cos(a), z = r * sin(a)
                if free(x, z, margin) { return SCNVector3(x, 0, z) }
            }
            return nil
        }

        // Grasflecken: flache Scheiben in zwei weiteren Gruentoenen - das
        // macht aus der Scheibe eine Wiese. Duerfen unter Baeumen liegen.
        for index in 0..<Int(radius * 4) {
            let r = rng.next(in: 0.2...(radius - 0.6))
            let a = rng.next(in: 0..<(2 * Float.pi))
            let patch = SCNCylinder(radius: CGFloat(rng.next(in: 0.35...0.9)), height: 0.02)
            patch.radialSegmentCount = 18
            patch.firstMaterial = material(index % 2 == 0 ? palette.grassLight : palette.grassDark)
            let node = SCNNode(geometry: patch)
            // Jeder Fleck auf eigener Hoehe: liegen zwei Flaechen exakt
            // gleich hoch, streiten sie bei jeder Kamerabewegung um den
            // Vordergrund - das war das Flackern der Wiese.
            node.position = SCNVector3(r * cos(a), 0.004 + 0.0006 * Float(index % 16), r * sin(a))
            node.scale = SCNVector3(1, 1, rng.next(in: 0.6...1))
            node.eulerAngles.y = rng.next(in: 0..<Float.pi)
            root.addChildNode(node)
        }

        // Der Teich: eine Wasserflaeche mit Sandrand und Seerosen. Am Rand
        // der Insel, denn zwischen der Spirale und der Kante bleibt immer ein
        // Streifen frei - mitten im Wald gaebe es bei vielen Baeumen keinen
        // Platz mehr. Erst ab dem dritten Baum.
        let pondRadius: Float = radius > 8 ? 1.1 : 0.8
        let shore = radius - pondRadius - 0.4
        for _ in 0..<(trees >= 3 ? 12 : 0) {
            let a = rng.next(in: 0..<(2 * Float.pi))
            let x = shore * cos(a), z = shore * sin(a)
            guard free(x, z, pondRadius + 0.45) else { continue }
            root.addChildNode(pond(radius: pondRadius, at: SCNVector3(x, 0, z), palette: palette, rng: &rng))
            break
        }

        // Blumen in vielen Farben, gern in kleinen Gruppen.
        let flowerColors = palette.flowers
        for _ in 0..<(2 + trees) {
            guard let center = place(0.35, rng: &rng) else { continue }
            let color = flowerColors[Int(rng.nextRaw() % UInt64(flowerColors.count))]
            let cluster = 1 + Int(rng.nextRaw() % 3)
            for _ in 0..<cluster {
                let node = flower(color: color, palette: palette, rng: &rng)
                node.position = SCNVector3(center.x + rng.next(in: -0.25...0.25), 0,
                                           center.z + rng.next(in: -0.25...0.25))
                root.addChildNode(node)
            }
        }

        // Pilze und Steine - wenige, dafuer auffaellig.
        for _ in 0..<(1 + trees / 4) {
            guard let position = place(0.4, rng: &rng) else { continue }
            let node = mushroom(palette: palette, rng: &rng)
            node.position = position
            root.addChildNode(node)
        }
        for _ in 0..<(1 + trees / 3) {
            guard let position = place(0.5, rng: &rng) else { continue }
            let stone = SCNSphere(radius: CGFloat(rng.next(in: 0.1...0.2)))
            stone.segmentCount = 10
            stone.firstMaterial = material(palette.stone)
            let node = SCNNode(geometry: stone)
            node.position = position
            node.scale = SCNVector3(rng.next(in: 1...1.6), 0.5, 1)
            node.eulerAngles.y = rng.next(in: 0..<Float.pi)
            root.addChildNode(node)
        }
    }

    private static func pond(radius: Float, at position: SCNVector3, palette: Palette,
                             rng: inout SeededRandom) -> SCNNode {
        let node = SCNNode()
        node.position = position
        let sand = SCNCylinder(radius: CGFloat(radius + 0.22), height: 0.04)
        sand.radialSegmentCount = 36
        sand.firstMaterial = material(palette.sand)
        let shore = SCNNode(geometry: sand)
        // Ueber allen Grasflecken (die enden bei 0,025).
        shore.position.y = 0.03
        node.addChildNode(shore)

        let water = SCNCylinder(radius: CGFloat(radius), height: 0.05)
        water.radialSegmentCount = 36
        let wet = SCNMaterial()
        wet.diffuse.contents = palette.water
        wet.specular.contents = UIColor.white
        wet.shininess = 0.6
        wet.lightingModel = .blinn
        water.firstMaterial = wet
        let surface = SCNNode(geometry: water)
        surface.position.y = 0.06
        node.addChildNode(surface)

        // Seerosen: flache gruene Scheiben mit einer rosa Bluete.
        for _ in 0..<3 {
            let pad = SCNCylinder(radius: 0.13, height: 0.02)
            pad.radialSegmentCount = 12
            pad.firstMaterial = material(palette.lilyPad)
            let leaf = SCNNode(geometry: pad)
            let r = rng.next(in: 0.15...(radius - 0.25))
            let a = rng.next(in: 0..<(2 * Float.pi))
            leaf.position = SCNVector3(r * cos(a), 0.1, r * sin(a))
            node.addChildNode(leaf)
            if rng.nextRaw() % 2 == 0 {
                let bloom = SCNSphere(radius: 0.06)
                bloom.segmentCount = 8
                bloom.firstMaterial = material(palette.lilyBloom)
                let flower = SCNNode(geometry: bloom)
                flower.position = SCNVector3(leaf.position.x, 0.15, leaf.position.z)
                node.addChildNode(flower)
            }
        }
        return node.flattenedClone()
    }

    private static func flower(color: UIColor, palette: Palette, rng: inout SeededRandom) -> SCNNode {
        let node = SCNNode()
        let height = rng.next(in: 0.12...0.22)
        let stem = SCNCylinder(radius: 0.015, height: CGFloat(height))
        stem.radialSegmentCount = 6
        stem.firstMaterial = material(palette.stem)
        let stalk = SCNNode(geometry: stem)
        stalk.position.y = height / 2
        node.addChildNode(stalk)
        let head = SCNSphere(radius: CGFloat(rng.next(in: 0.05...0.08)))
        head.segmentCount = 8
        head.firstMaterial = material(color)
        let bloom = SCNNode(geometry: head)
        bloom.position.y = height + 0.03
        bloom.scale = SCNVector3(1, 0.7, 1)
        node.addChildNode(bloom)
        return node.flattenedClone()
    }

    /// Der Busch: ein Haufen aus vier Kugeln, dunkler als die Kronen, ohne
    /// Stamm. Eine Session von einer halben Stunde wird eher ein Busch als
    /// ein Baum - und auch Buesche stehen fuer Fokus.
    private static func bushCrown(_ node: SCNNode, palette: Palette, rng: inout SeededRandom) {
        let leaf = material(palette.bush(shift: rng.next(in: -0.03...0.03)))
        for index in 0..<4 {
            let r = rng.next(in: 0.36...0.5)
            let ball = SCNSphere(radius: CGFloat(r))
            ball.segmentCount = 12
            ball.firstMaterial = leaf
            let part = SCNNode(geometry: ball)
            let angle = Float(index) * 1.6
            part.position = SCNVector3(cos(angle) * 0.28, r * 0.8, sin(angle) * 0.28)
            node.addChildNode(part)
        }
    }

    private static func mushroom(palette: Palette, rng: inout SeededRandom) -> SCNNode {
        let node = SCNNode()
        let stem = SCNCylinder(radius: 0.035, height: 0.11)
        stem.radialSegmentCount = 8
        stem.firstMaterial = material(palette.mushroomStem)
        let stalk = SCNNode(geometry: stem)
        stalk.position.y = 0.055
        node.addChildNode(stalk)
        let cap = SCNSphere(radius: 0.09)
        cap.segmentCount = 10
        cap.firstMaterial = material(palette.mushroomCap)
        let hat = SCNNode(geometry: cap)
        hat.position.y = 0.12
        hat.scale = SCNVector3(1, 0.6, 1)
        node.addChildNode(hat)
        for index in 0..<3 {
            let dot = SCNSphere(radius: 0.02)
            dot.segmentCount = 6
            dot.firstMaterial = material(UIColor.white)
            let spot = SCNNode(geometry: dot)
            let angle = Float(index) * 2.2 + rng.next(in: 0...0.5)
            spot.position = SCNVector3(cos(angle) * 0.05, 0.16, sin(angle) * 0.05)
            node.addChildNode(spot)
        }
        let size = rng.next(in: 0.8...1.3)
        node.scale = SCNVector3(size, size, size)
        return node.flattenedClone()
    }

    // MARK: - Himmel und Leben

    /// Am Tag Schmetterlinge und Wolken, nachts Gluehwuermchen: alles
    /// kreist langsam um die Insel und wippt dabei - das bisschen Bewegung
    /// macht den Unterschied zwischen Modell und Wald.
    private static func animateSky(_ root: SCNNode, radius: Float, trees: Int, palette: Palette,
                                   rng: inout SeededRandom) {
        let flyers = min(palette.night ? 7 : 5, 1 + trees / 3)
        for _ in 0..<flyers {
            let pivot = SCNNode()
            let body = SCNSphere(radius: palette.night ? 0.045 : 0.06)
            body.segmentCount = 8
            let skin = SCNMaterial()
            let color = palette.flyerColors[Int(rng.nextRaw() % UInt64(palette.flyerColors.count))]
            skin.diffuse.contents = color
            skin.emission.contents = palette.night ? color : UIColor.black
            skin.lightingModel = .lambert
            body.firstMaterial = skin
            let flyer = SCNNode(geometry: body)
            flyer.scale = palette.night ? SCNVector3(1, 1, 1) : SCNVector3(1.6, 0.5, 1)
            flyer.position = SCNVector3(rng.next(in: (radius * 0.2)...(radius * 0.85)),
                                        rng.next(in: 0.6...2.2), 0)
            let bob = SCNAction.sequence([
                .moveBy(x: 0, y: CGFloat(rng.next(in: 0.1...0.3)), z: 0, duration: Double(rng.next(in: 0.8...1.6))),
                .moveBy(x: 0, y: CGFloat(-rng.next(in: 0.1...0.3)), z: 0, duration: Double(rng.next(in: 0.8...1.6))),
            ])
            bob.timingMode = .easeInEaseOut
            flyer.runAction(.repeatForever(bob))
            if palette.night {
                // Gluehwuermchen blinken.
                let blink = SCNAction.sequence([
                    .fadeOpacity(to: 0.15, duration: Double(rng.next(in: 0.6...1.4))),
                    .fadeOpacity(to: 1, duration: Double(rng.next(in: 0.4...1.0))),
                ])
                flyer.runAction(.repeatForever(blink))
            }
            pivot.addChildNode(flyer)
            pivot.eulerAngles.y = rng.next(in: 0..<(2 * Float.pi))
            let direction: CGFloat = rng.nextRaw() % 2 == 0 ? 1 : -1
            pivot.runAction(.repeatForever(.rotateBy(x: 0, y: direction * .pi * 2, z: 0,
                                                     duration: Double(rng.next(in: 18...45)))))
            root.addChildNode(pivot)
        }

        // Wolken: weiche Haufen aus drei Kugeln, hoch ueber der Insel.
        for _ in 0..<min(3 + Int(radius / 4), 1 + trees / 2) {
            let pivot = SCNNode()
            let cloud = SCNNode()
            let puff = material(palette.cloud)
            for index in 0..<3 {
                let ball = SCNSphere(radius: CGFloat(rng.next(in: 0.45...0.8)))
                ball.segmentCount = 12
                ball.firstMaterial = puff
                let part = SCNNode(geometry: ball)
                part.position = SCNVector3(Float(index - 1) * 0.65, Float(index == 1 ? 0.2 : 0), 0)
                cloud.addChildNode(part)
            }
            cloud.scale = SCNVector3(1, 0.55, 0.8)
            cloud.position = SCNVector3(rng.next(in: (radius * 0.4)...(radius * 1.2)),
                                        rng.next(in: 4.5...7), 0)
            pivot.addChildNode(cloud.flattenedClone())
            pivot.eulerAngles.y = rng.next(in: 0..<(2 * Float.pi))
            pivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0,
                                                     duration: Double(rng.next(in: 150...260)))))
            root.addChildNode(pivot)
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

    enum Species {
        case pine, oak, birch, blossom, autumn, cypress, bush
    }

    /// Welche Art ein Baum wird - bunt gemischt, Tannen und Eichen am
    /// haeufigsten, dazwischen Farbe. Kurze Sessions werden gern ein Busch,
    /// lange nie: ein vier Stunden hoher Busch waere seltsam.
    private static func species(size: TreeSize, _ rng: inout SeededRandom) -> Species {
        let bushChance: Float = switch size {
        case .sapling: 0.45
        case .young:   0.2
        case .grown, .old: 0
        }
        if rng.next(in: 0..<1) < bushChance { return .bush }
        return switch rng.next(in: 0..<1) {
        case ..<0.28: .pine
        case ..<0.52: .oak
        case ..<0.68: .birch
        case ..<0.80: .blossom
        case ..<0.92: .autumn
        default:      .cypress
        }
    }

    /// Ein Baum: Art aus dem Zufall, Groesse aus der Dauer, dazu ein wenig
    /// Streuung in Drehung, Groesse und Farbton - aus der Session-Id, damit er
    /// bei jedem Bild derselbe ist.
    private static func tree(minutes: Int, rng: inout SeededRandom, palette: Palette) -> SCNNode {
        let node = SCNNode()
        let shift = rng.next(in: -0.04...0.04)
        let size = TreeSize(minutes: minutes)
        switch species(size: size, &rng) {
        case .bush:
            bushCrown(node, palette: palette, rng: &rng)
        case .pine:
            let crown = material(palette.pine(shift: shift))
            node.addChildNode(trunk(height: 0.6, radius: 0.09, material(palette.bark)))
            node.addChildNode(cone(bottom: 0.72, height: 0.8, y: 0.55, crown))
            node.addChildNode(cone(bottom: 0.56, height: 0.7, y: 1.05, crown))
            node.addChildNode(cone(bottom: 0.38, height: 0.6, y: 1.55, crown))
        case .oak:
            let crown = material(palette.leaf(shift: shift))
            node.addChildNode(trunk(height: 0.9, radius: 0.13, material(palette.bark)))
            node.addChildNode(ball(radius: 0.75, y: 1.4, crown))
            node.addChildNode(ball(radius: 0.5, y: 1.75, crown, x: 0.45, z: 0.1))
            node.addChildNode(ball(radius: 0.48, y: 1.7, crown, x: -0.42, z: 0.25))
            node.addChildNode(ball(radius: 0.45, y: 2.05, crown, z: -0.2))
        case .birch:
            let crown = material(palette.birchLeaf(shift: shift))
            node.addChildNode(trunk(height: 1.2, radius: 0.06, material(palette.birchBark)))
            node.addChildNode(ball(radius: 0.4, y: 1.35, crown, scaleY: 1.35))
            node.addChildNode(ball(radius: 0.3, y: 1.7, crown, x: 0.25, scaleY: 1.2))
            node.addChildNode(ball(radius: 0.28, y: 1.65, crown, x: -0.24, z: 0.12, scaleY: 1.2))
        case .blossom:
            let crown = material(palette.blossom(shift: shift))
            let light = material(palette.blossomLight)
            node.addChildNode(trunk(height: 0.7, radius: 0.1, material(palette.darkBark)))
            node.addChildNode(ball(radius: 0.62, y: 1.1, crown))
            node.addChildNode(ball(radius: 0.42, y: 1.45, light, x: 0.4))
            node.addChildNode(ball(radius: 0.4, y: 1.4, light, x: -0.35, z: 0.25))
            node.addChildNode(ball(radius: 0.36, y: 1.7, crown, z: -0.15))
        case .autumn:
            node.addChildNode(trunk(height: 0.8, radius: 0.11, material(palette.darkBark)))
            let tones = palette.autumn
            node.addChildNode(ball(radius: 0.65, y: 1.25, material(tones[0])))
            node.addChildNode(ball(radius: 0.45, y: 1.6, material(tones[1]), x: 0.42))
            node.addChildNode(ball(radius: 0.42, y: 1.55, material(tones[2]), x: -0.4, z: 0.2))
            node.addChildNode(ball(radius: 0.4, y: 1.9, material(tones[1]), z: -0.15))
        case .cypress:
            let crown = material(palette.cypress(shift: shift))
            node.addChildNode(trunk(height: 0.3, radius: 0.07, material(palette.bark)))
            let body = SCNCone(topRadius: 0.03, bottomRadius: 0.38, height: 2.0)
            body.radialSegmentCount = 14
            body.firstMaterial = crown
            let spire = SCNNode(geometry: body)
            spire.position = SCNVector3(0, 1.25, 0)
            node.addChildNode(spire)
        }
        let scale = size.scale * rng.next(in: 0.92...1.08)
        node.scale = SCNVector3(scale, scale, scale)
        node.eulerAngles.y = rng.next(in: 0..<(2 * Float.pi))
        // Ein Knoten je Baum statt fuenf: weniger Zeichenaufrufe bei einem
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
                             x: Float = 0, z: Float = 0, scaleY: Float = 1) -> SCNNode {
        let geometry = SCNSphere(radius: CGFloat(radius))
        geometry.segmentCount = 18
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(x, y, z)
        node.scale = SCNVector3(1, scaleY, 1)
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
        let phase: Daylight.Phase

        var night: Bool { phase == .night }
        var dusk: Bool { phase == .dusk }

        private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
            UIColor(red: r, green: g, blue: b, alpha: 1)
        }

        private func shade(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat, shift: Float = 0) -> UIColor {
            // Nachts alles dunkler und kuehler.
            UIColor(hue: h + CGFloat(shift) + (night ? 0.02 : 0),
                    saturation: night ? s * 0.8 : s,
                    brightness: night ? b * 0.5 : b, alpha: 1)
        }

        var grass: UIColor { shade(0.27, 0.55, 0.72) }
        var grassLight: UIColor { shade(0.24, 0.5, 0.8) }
        var grassDark: UIColor { shade(0.3, 0.6, 0.62) }
        var soil: UIColor { night ? rgb(0.24, 0.18, 0.14) : rgb(0.5, 0.36, 0.25) }
        var soilLight: UIColor { night ? rgb(0.3, 0.23, 0.17) : rgb(0.62, 0.47, 0.33) }
        var sand: UIColor { night ? rgb(0.45, 0.42, 0.34) : rgb(0.9, 0.84, 0.62) }
        var water: UIColor { night ? rgb(0.12, 0.22, 0.4) : rgb(0.36, 0.68, 0.92) }
        var lilyPad: UIColor { shade(0.33, 0.55, 0.6) }
        var lilyBloom: UIColor { night ? rgb(0.7, 0.45, 0.6) : rgb(0.98, 0.62, 0.78) }
        var bark: UIColor { night ? rgb(0.28, 0.2, 0.14) : rgb(0.47, 0.32, 0.2) }
        var darkBark: UIColor { night ? rgb(0.22, 0.15, 0.11) : rgb(0.36, 0.24, 0.16) }
        var birchBark: UIColor { night ? rgb(0.55, 0.55, 0.5) : rgb(0.93, 0.92, 0.86) }
        var stem: UIColor { shade(0.3, 0.6, 0.55) }
        var stone: UIColor { night ? rgb(0.35, 0.36, 0.38) : rgb(0.6, 0.6, 0.62) }
        var mushroomCap: UIColor { night ? rgb(0.55, 0.15, 0.12) : rgb(0.88, 0.22, 0.18) }
        var mushroomStem: UIColor { night ? rgb(0.6, 0.58, 0.5) : rgb(0.96, 0.94, 0.86) }
        var cloud: UIColor {
            switch phase {
            case .day:   rgb(0.99, 0.99, 1.0)
            case .dusk:  rgb(1.0, 0.82, 0.78)
            case .night: rgb(0.35, 0.38, 0.5)
            }
        }

        var flowers: [UIColor] {
            night ? [rgb(0.75, 0.72, 0.6), rgb(0.7, 0.5, 0.55), rgb(0.55, 0.55, 0.75), rgb(0.7, 0.6, 0.35)]
                  : [rgb(1.0, 0.85, 0.25), rgb(0.98, 0.98, 0.95), rgb(0.95, 0.3, 0.3),
                     rgb(0.98, 0.55, 0.7), rgb(0.55, 0.45, 0.85), rgb(0.35, 0.55, 0.95),
                     rgb(1.0, 0.6, 0.2)]
        }
        /// Schmetterlinge am Tag, Gluehwuermchen in der Nacht.
        var flyerColors: [UIColor] {
            night ? [rgb(1.0, 0.95, 0.5), rgb(0.85, 1.0, 0.6)]
                  : [rgb(1.0, 0.85, 0.3), rgb(1.0, 1.0, 1.0), rgb(1.0, 0.6, 0.3), rgb(0.6, 0.75, 1.0)]
        }
        var autumn: [UIColor] {
            night ? [rgb(0.5, 0.28, 0.1), rgb(0.45, 0.15, 0.1), rgb(0.5, 0.4, 0.12)]
                  : [rgb(0.98, 0.55, 0.15), rgb(0.85, 0.28, 0.18), rgb(0.98, 0.8, 0.25)]
        }

        func pine(shift: Float) -> UIColor { shade(0.38, 0.6, 0.42, shift: shift) }
        func leaf(shift: Float) -> UIColor { shade(0.31, 0.62, 0.66, shift: shift) }
        func birchLeaf(shift: Float) -> UIColor { shade(0.25, 0.5, 0.82, shift: shift) }
        func cypress(shift: Float) -> UIColor { shade(0.4, 0.55, 0.36, shift: shift) }
        func bush(shift: Float) -> UIColor { shade(0.34, 0.6, 0.5, shift: shift) }
        func blossom(shift: Float) -> UIColor {
            night ? rgb(0.6, 0.4, 0.5) : UIColor(hue: 0.93 + CGFloat(shift), saturation: 0.45, brightness: 0.98, alpha: 1)
        }
        var blossomLight: UIColor { night ? rgb(0.7, 0.55, 0.62) : rgb(1.0, 0.85, 0.9) }

        var skyTop: UIColor {
            switch phase {
            case .day:   rgb(0.5, 0.75, 0.95)
            case .dusk:  rgb(0.28, 0.24, 0.5)
            case .night: rgb(0.04, 0.06, 0.16)
            }
        }
        var skyBottom: UIColor {
            switch phase {
            case .day:   rgb(0.9, 0.95, 0.99)
            case .dusk:  rgb(0.99, 0.66, 0.42)
            case .night: rgb(0.14, 0.18, 0.32)
            }
        }
        var fog: UIColor { skyBottom }
        var sunIntensity: CGFloat {
            switch phase {
            case .day: 1100
            case .dusk: 800
            case .night: 420
            }
        }
        var sunColor: UIColor {
            switch phase {
            case .day:   rgb(1.0, 0.96, 0.88)
            case .dusk:  rgb(1.0, 0.72, 0.5)
            case .night: rgb(0.75, 0.82, 1.0)
            }
        }
        var ambientIntensity: CGFloat {
            switch phase {
            case .day: 430
            case .dusk: 380
            case .night: 240
            }
        }
        var ambientColor: UIColor {
            switch phase {
            case .day:   rgb(1, 1, 1)
            case .dusk:  rgb(0.95, 0.8, 0.85)
            case .night: rgb(0.6, 0.7, 1.0)
            }
        }

        /// Der Himmel als Bild: Verlauf, dazu die Sonne dort, wo sie steht -
        /// hoch am Tag, tief und orange in der Daemmerung -, nachts Sterne
        /// und Mond. SceneKit nimmt fuer den Hintergrund ein Bild, und im Bild
        /// kostet das nichts.
        func skyImage(sun: Daylight.Sun) -> UIImage {
            let size = CGSize(width: 512, height: 768)
            return UIGraphicsImageRenderer(size: size).image { context in
                let cg = context.cgContext
                let colors = [skyTop.cgColor, skyBottom.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero,
                                          end: CGPoint(x: 0, y: size.height), options: [])
                }
                var rng = SeededRandom(seed: 0x51A9)
                if night {
                    for _ in 0..<140 {
                        let x = CGFloat(rng.next(in: 0...1)) * size.width
                        let y = CGFloat(rng.next(in: 0...0.75)) * size.height
                        let r = CGFloat(rng.next(in: 0.6...1.8))
                        cg.setFillColor(UIColor.white.withAlphaComponent(CGFloat(rng.next(in: 0.35...1))).cgColor)
                        cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                    }
                    let moon = CGRect(x: size.width * 0.72, y: size.height * 0.14, width: 44, height: 44)
                    cg.setFillColor(UIColor(red: 0.98, green: 0.96, blue: 0.82, alpha: 0.18).cgColor)
                    cg.fillEllipse(in: moon.insetBy(dx: -22, dy: -22))
                    cg.setFillColor(UIColor(red: 0.98, green: 0.96, blue: 0.82, alpha: 1).cgColor)
                    cg.fillEllipse(in: moon)
                } else {
                    // Hoehe im Bild aus der Sonnenhoehe: mittags oben, in der
                    // Daemmerung knapp ueber der Insel.
                    let height = CGFloat(max(0, min(1, sun.elevation / (Double.pi / 3))))
                    let center = CGPoint(x: size.width * 0.78, y: size.height * (0.5 - 0.36 * height))
                    let glow = dusk
                        ? [UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.98).cgColor,
                           UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 0).cgColor] as CFArray
                        : [UIColor(red: 1, green: 0.98, blue: 0.85, alpha: 0.95).cgColor,
                           UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 0).cgColor] as CFArray
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                 colors: glow, locations: [0, 1]) {
                        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                              endCenter: center, endRadius: dusk ? 150 : 110, options: [])
                    }
                }
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

/// Die Szene in SwiftUI. Neu gebaut, wenn sich Baeume, laufende Session
/// oder der Sonnenstand aendern - der wachsende Baum waechst dazwischen als
/// Aktion. Tag und Nacht folgen der Uhr, nicht dem Dunkelmodus: Felix wollte
/// die Insel nicht dauernd bei Nacht sehen (2026-09-22). Alle fuenf Minuten
/// wird der Sonnenstand neu gelesen, gebaut aber nur, wenn er sich merklich
/// bewegt hat (Zehntelgrad-Stufen alle paar Minuten reichen nicht).
struct ForestSceneView: View {

    let sessions: [FocusSession]
    let active: ActiveSession?

    @State private var scene: SCNScene?

    private struct Key: Equatable {
        let ids: [String]
        let activeID: String?
        let phase: Daylight.Phase
        /// Sonnenhoehe und -richtung in groben Stufen, damit die Sonne
        /// ueber den Tag wandert, ohne die Szene minuetlich neu zu bauen.
        let elevationStep: Int
        let azimuthStep: Int
    }

    private func key(at date: Date) -> Key {
        let sun = Daylight.sun(at: date)
        return Key(ids: sessions.map(\.id), activeID: active?.id, phase: sun.phase,
                   elevationStep: Int((sun.elevation * 20).rounded()),
                   azimuthStep: Int((sun.azimuth * 12).rounded()))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            SceneView(scene: scene,
                      options: [.rendersContinuously],
                      preferredFramesPerSecond: 30,
                      antialiasingMode: .multisampling4X)
                .task(id: key(at: context.date)) {
                    scene = ForestScene.build(sessions: sessions, active: active,
                                              sun: Daylight.sun(at: context.date))
                }
        }
    }
}
