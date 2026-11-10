import Foundation

/// An welchen Rechner von Apple der Kalorienzaehler die Benachrichtigungen fuer
/// dieses Geraet schicken muss (Vertrag §11.2).
///
/// Felix' iPhone bekommt Healthy als Entwickler-Install (`install-device.sh`),
/// ein zweites iPhone ueber TestFlight. Die Push-Kennungen der beiden stammen
/// aus verschiedenen Welten: schickt der Dienst eine Produktions-Kennung an die
/// Sandbox, antwortet Apple mit `BadDeviceToken` - und der Dienst wirft sie weg.
///
/// Die Entitlements bleiben fuer beide Wege dieselben (`aps-environment:
/// development` in project.yml): beim Export fuer TestFlight signiert Xcode
/// neu und setzt `production` aus dem Verteilungsprofil. iOS verraet einer App
/// ihre eigenen Entitlements nicht - aber das Profil liegt lesbar im Bundle.
enum APNsEnvironment: String, Sendable {
    case sandbox
    case production

    static var current: APNsEnvironment {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return detect(profile: profile, isSimulator: isSimulator, isDebugBuild: isDebugBuild)
    }

    /// Rein, damit die Regel ohne Geraet pruefbar ist.
    ///
    /// - Parameter profile: der Inhalt von `embedded.mobileprovision`. Ein
    ///   Entwickler- oder Ad-hoc-Install hat die Datei; was ueber TestFlight
    ///   oder den App Store kommt, hat sie nicht mehr.
    static func detect(profile: Data?, isSimulator: Bool, isDebugBuild: Bool) -> APNsEnvironment {
        // Der Simulator bekommt seine Kennungen immer aus der Sandbox.
        if isSimulator { return .sandbox }
        guard let profile else { return .production }
        switch apsEnvironment(inProfile: profile) {
        case "production":  return .production
        case "development": return .sandbox
        // Profil da, aber nicht zu lesen: dann sagt die Bauart am ehesten,
        // woher die Signatur kommt.
        default:            return isDebugBuild ? .sandbox : .production
        }
    }

    /// Das Profil ist eine signierte Huelle um eine Property-List im Klartext.
    static func apsEnvironment(inProfile profile: Data) -> String? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex)
        else { return nil }
        let plist = profile.subdata(in: start.lowerBound..<end.upperBound)
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any]
        else { return nil }
        return entitlements["aps-environment"] as? String
    }
}
