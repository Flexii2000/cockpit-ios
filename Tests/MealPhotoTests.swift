import UIKit
import XCTest
@testable import Healthy

/// Das Foto fuer die Schnellerfassung: klein genug fuer die Anfrage, als
/// JPEG, als Base64 ohne Praefix.
final class MealPhotoTests: XCTestCase {

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testLongEdgeIsCappedAndAspectKept() {
        let resized = MealPhoto.resized(image(width: 4032, height: 3024))
        XCTAssertEqual(resized.size.width, 1280)
        XCTAssertEqual(resized.size.height, 960)
        let small = MealPhoto.resized(image(width: 640, height: 480))
        XCTAssertEqual(small.size.width, 640, "kleine Bilder bleiben, wie sie sind")
    }

    func testBase64IsAJpegWithoutPrefix() throws {
        let base64 = try XCTUnwrap(MealPhoto.base64(image(width: 2000, height: 1500)))
        XCTAssertFalse(base64.hasPrefix("data:"))
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual([UInt8](data.prefix(2)), [0xFF, 0xD8], "JPEG beginnt mit FF D8")
        XCTAssertLessThan(data.count, 600_000, "ein einfarbiges 1280er-Bild ist winzig, ein Foto ~200 kB")
    }
}
