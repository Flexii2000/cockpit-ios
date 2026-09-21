import Testing
@testable import Healthy

/// Was der Scanner liefert, wird zur GTIN, die Open Food Facts kennt - oder
/// zu nichts, wenn es kein Produktcode ist.
struct ProductCodeTests {

    @Test func eanDigitsPassThrough() {
        #expect(ProductCode.gtin(from: "4000417025005") == "4000417025005")
        #expect(ProductCode.gtin(from: "40111445") == "40111445")
        #expect(ProductCode.gtin(from: "012345678905") == "012345678905")
        #expect(ProductCode.gtin(from: " 4000417025005\n") == "4000417025005")
    }

    /// GTIN-14 mit Packungskennzeichen 0 ist dieselbe Artikelnummer wie die
    /// EAN-13 - und unter der steht sie in der Datenbank.
    @Test func gtin14DropsTheLeadingZero() {
        #expect(ProductCode.gtin(from: "04000417025005") == "4000417025005")
        #expect(ProductCode.gtin(from: "14000417025002") == "14000417025002")
    }

    @Test func gs1DigitalLinkYieldsTheGtin() {
        #expect(ProductCode.gtin(from: "https://id.gs1.org/01/04000417025005/10/ABC123?17=261231")
                == "4000417025005")
        #expect(ProductCode.gtin(from: "https://example.com/01/4000417025005") == "4000417025005")
        #expect(ProductCode.gtin(from: "http://example.com/shop/gtin/40111445") == "40111445")
    }

    /// DataMatrix und GS1 DataBar tragen Elementstrings: Bezeichner 01, dann
    /// 14 Ziffern, dann Charge und Haltbarkeit.
    @Test func gs1ElementStringYieldsTheGtin() {
        #expect(ProductCode.gtin(from: "(01)04000417025005(17)261231(10)AB12") == "4000417025005")
        #expect(ProductCode.gtin(from: "0104000417025005172612311AB12") == "4000417025005")
        #expect(ProductCode.gtin(from: "0104000417025005") == "4000417025005")
    }

    @Test func otherQrContentIsNoProductCode() {
        #expect(ProductCode.gtin(from: "https://www.ritter-sport.de/") == nil)
        #expect(ProductCode.gtin(from: "https://example.com/01/abc") == nil)
        #expect(ProductCode.gtin(from: "Hallo Welt") == nil)
        #expect(ProductCode.gtin(from: "WIFI:T:WPA;S:Netz;P:geheim;;") == nil)
        #expect(ProductCode.gtin(from: "12345") == nil)
        #expect(ProductCode.gtin(from: "123456789012345") == nil)
        #expect(ProductCode.gtin(from: "(01)0400041702500") == nil)
        #expect(ProductCode.gtin(from: "") == nil)
    }
}
