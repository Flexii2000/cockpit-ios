import CryptoKit
import XCTest
@testable import Fokus

/// Was Fokus beim Freigeben signiert. Derselbe Testvektor steht im Gate
/// (`gate/src/test/java/com/fherrmann/gate/approval/CanonicalTest.java` im
/// Assistent-Repo) - aendert sich einer, lehnt das Gate jede Freigabe ab.
final class ApprovalPayloadTests: XCTestCase {

    private let fields = [
        ApprovalField(name: "an", wert: "Max Muster <max@example.com>"),
        ApprovalField(name: "cc", wert: ""),
        ApprovalField(name: "betreff", wert: "Grüße aus Hamburg"),
        ApprovalField(name: "text", wert: "Hallo Max,\n\nZeile 2 = gleich & mehr.\n"),
    ]

    func testTextAndHashMatchTheSharedVector() {
        XCTAssertEqual(ApprovalPayload.text(art: "mail", fields: fields), """
            assistant-gate/v1
            art=bWFpbA==
            an=TWF4IE11c3RlciA8bWF4QGV4YW1wbGUuY29tPg==
            cc=
            betreff=R3LDvMOfZSBhdXMgSGFtYnVyZw==
            text=SGFsbG8gTWF4LAoKWmVpbGUgMiA9IGdsZWljaCAmIG1laHIuCg==

            """)
        XCTAssertEqual(ApprovalPayload.hash(art: "mail", fields: fields),
                       "893b8bacf7b8105af0d4c0e72a8889282cf7909a3b59d746da78e993804d67db")
    }

    func testMessageBindsIdHashAndTime() {
        XCTAssertEqual(ApprovalPayload.message(id: "abc", hash: "ff", time: 1_700_000_000),
                       "assistant-gate/v1|abc|ff|1700000000")
    }

    func testChangedContentChangesTheHash() {
        let original = ApprovalPayload.hash(art: "mail", fields: fields)
        var changed = fields
        changed[0] = ApprovalField(name: "an", wert: "boese@example.com")
        XCTAssertNotEqual(ApprovalPayload.hash(art: "mail", fields: changed), original)
        XCTAssertNotEqual(ApprovalPayload.hash(art: "ueberweisung", fields: fields), original)
        XCTAssertNotEqual(ApprovalPayload.hash(art: "mail", fields: fields.reversed()), original)
    }

    /// Wie `setup-gate.sh` ihn zeigt: `base64 -d | sha256sum | cut -c1-16`, in Vierergruppen.
    func testFingerprintMatchesTheSetupScript() {
        XCTAssertEqual(ApprovalPayload.fingerprint(publicKeyDER: Data(0..<91)), "58d2 9459 b213 0a2e")
    }

    /// Software-Schluessel statt Secure Enclave (gibt es im Simulator nicht) -
    /// die Formate sind dieselben: SubjectPublicKeyInfo und DER-Signatur.
    func testSignatureFormatsAreWhatTheGateParses() throws {
        let key = P256.Signing.PrivateKey()
        let message = ApprovalPayload.message(id: "id", hash: ApprovalPayload.hash(art: "mail", fields: fields),
                                              time: 1_700_000_000)
        let signature = try key.signature(for: Data(message.utf8))
        let der = signature.derRepresentation
        XCTAssertEqual(der.first, 0x30, "DER-SEQUENCE")
        let parsed = try P256.Signing.ECDSASignature(derRepresentation: der)
        XCTAssertTrue(key.publicKey.isValidSignature(parsed, for: Data(message.utf8)))
        XCTAssertEqual(key.publicKey.derRepresentation.count, 91, "SubjectPublicKeyInfo fuer P-256")
    }

    func testStatusFromTheServerAndUnknownValues() throws {
        let json = Data(#"""
        [{"id":"a","art":"mail","titel":"An x: y","status":"WARTET","erstellt":"2026-11-17T10:00:00Z",
          "erledigt":null,"ergebnis":null},
         {"id":"b","art":"mail","titel":"An x: z","status":"NEU_IN_ZUKUNFT","erstellt":"2026-11-17T10:00:00Z",
          "erledigt":"2026-11-17T10:01:00Z","ergebnis":"ok"}]
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try decoder.decode([ApprovalSummary].self, from: json)
        XCTAssertEqual(items.map(\.status), [.wartet, .unbekannt])
    }

    func testRecipientsFromTheGateAndIbanFormat() throws {
        let json = Data(#"""
        [{"iban":"DE89370400440532013000","name":"Person A","seit":"2026-11-17T10:00:00Z","quelle":"import","freigabeId":"x"}]
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode([ApprovalRecipient].self, from: json)
        XCTAssertEqual(list.map(\.name), ["Person A"])
        XCTAssertEqual(ApprovalRecipient.format(iban: list[0].iban), "DE89 3704 0044 0532 0130 00")
        XCTAssertEqual(ApprovalRecipient.format(iban: "gb82west12345698765432"), "GB82 WEST 1234 5698 7654 32")
    }

    /// Ueberweisungen und Empfaenger zeigen alle signierten Felder mit Namen.
    func testLabelsForMoneyApprovals() {
        XCTAssertEqual(["name", "iban", "betrag", "zweck", "ausfuehrung", "liste", "anzahl"]
            .map(ApprovalDetailView.label),
                       ["Empfänger", "IBAN", "Betrag", "Verwendungszweck", "Ausführung", "Empfänger", "Anzahl"])
        XCTAssertEqual(ApprovalDetailView.title("empfaengerliste"), "Empfängerliste")
    }
}
