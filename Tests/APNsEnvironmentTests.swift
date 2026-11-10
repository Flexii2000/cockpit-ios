import XCTest
@testable import Healthy

/// An welchen Rechner von Apple der Kalorienzaehler schicken muss - gelesen aus
/// dem Profil im Bundle. Ein falscher Wert kostet die Push-Kennung: der Dienst
/// wirft sie nach `BadDeviceToken` weg.
final class APNsEnvironmentTests: XCTestCase {

    /// Ein Profil ist eine signierte Huelle um eine Property-List im Klartext -
    /// davor und dahinter stehen Bytes, die kein Text sind.
    private func profile(aps: String?) -> Data {
        let entitlement = aps.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>Beispielprofil</string>
            <key>Entitlements</key>
            <dict>
                \(entitlement)
                <key>get-task-allow</key><true/>
            </dict>
        </dict>
        </plist>
        """
        return Data([0x30, 0x82, 0x1F, 0xFF, 0x00, 0x06]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x00, 0xFE])
    }

    func testTheSimulatorIsAlwaysSandbox() {
        XCTAssertEqual(APNsEnvironment.detect(profile: nil, isSimulator: true, isDebugBuild: false), .sandbox)
        XCTAssertEqual(APNsEnvironment.detect(profile: profile(aps: "production"), isSimulator: true,
                                              isDebugBuild: true), .sandbox)
    }

    /// Der Entwickler-Install auf Felix' iPhone.
    func testADevelopmentProfileIsSandbox() {
        XCTAssertEqual(APNsEnvironment.detect(profile: profile(aps: "development"), isSimulator: false,
                                              isDebugBuild: true), .sandbox)
        // Auch ein Release-Bau mit Entwicklungssignatur bleibt Sandbox - die
        // Signatur entscheidet, nicht die Bauart.
        XCTAssertEqual(APNsEnvironment.detect(profile: profile(aps: "development"), isSimulator: false,
                                              isDebugBuild: false), .sandbox)
    }

    func testAnAdHocProfileWithProductionIsProduction() {
        XCTAssertEqual(APNsEnvironment.detect(profile: profile(aps: "production"), isSimulator: false,
                                              isDebugBuild: false), .production)
    }

    /// TestFlight und App Store: das Profil liegt nicht mehr im Bundle.
    func testWithoutAProfileItIsProduction() {
        XCTAssertEqual(APNsEnvironment.detect(profile: nil, isSimulator: false, isDebugBuild: false), .production)
        XCTAssertEqual(APNsEnvironment.detect(profile: nil, isSimulator: false, isDebugBuild: true), .production)
    }

    /// Profil da, aber nicht zu lesen oder ohne Push: dann sagt die Bauart am
    /// ehesten, woher die Signatur kommt.
    func testAnUnreadableProfileFallsBackToTheBuild() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertEqual(APNsEnvironment.detect(profile: garbage, isSimulator: false, isDebugBuild: true), .sandbox)
        XCTAssertEqual(APNsEnvironment.detect(profile: garbage, isSimulator: false, isDebugBuild: false), .production)
        XCTAssertEqual(APNsEnvironment.detect(profile: profile(aps: nil), isSimulator: false, isDebugBuild: true),
                       .sandbox)
        XCTAssertNil(APNsEnvironment.apsEnvironment(inProfile: garbage))
        XCTAssertEqual(APNsEnvironment.apsEnvironment(inProfile: profile(aps: "development")), "development")
    }

    /// So geht es zum Dienst (Vertrag §11.2).
    func testTheWireValues() {
        XCTAssertEqual(APNsEnvironment.sandbox.rawValue, "sandbox")
        XCTAssertEqual(APNsEnvironment.production.rawValue, "production")
    }
}
