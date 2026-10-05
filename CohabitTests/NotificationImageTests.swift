import XCTest
@testable import coHabit

/// Was die Notification Service Extension laedt (Vertrag §2.7a, §4): ein Foto
/// nur vom eigenen Dienst und mit Token, ein GIF nur von KLIPYs Medien-Hosts,
/// die Anlage mit der Endung, an der iOS das Bild erkennt.
final class NotificationImageTests: XCTestCase {

    private let base = URL(string: "https://fherrmann.com/cohabit/api")!

    func testSourceFromTheDataFields() {
        XCTAssertEqual(NotificationImage.source(from: ["photoId": "p-1a2b", "kind": "photo"]), .photo(id: "p-1a2b"))
        let gif = "https://static.klipy.com/ii/935d/14/af/8GCrVAB7.gif"
        XCTAssertEqual(NotificationImage.source(from: ["imageUrl": gif, "imageStillUrl": "https://static.klipy.com/x.jpg"]),
                       .klipy(URL(string: gif)!))
        // Das Foto geht vor.
        XCTAssertEqual(NotificationImage.source(from: ["photoId": "p1", "imageUrl": gif]), .photo(id: "p1"))
        // Sammelnachricht ohne Bild, kaputte Felder.
        XCTAssertNil(NotificationImage.source(from: ["kind": "chat", "title": "3 neue Nachrichten"]))
        XCTAssertNil(NotificationImage.source(from: ["photoId": "../me/export"]), "kein Pfad als Kennung")
        XCTAssertNil(NotificationImage.source(from: ["photoId": ""]))
        XCTAssertNil(NotificationImage.source(from: ["photoId": 42]))
        XCTAssertNil(NotificationImage.source(from: ["imageUrl": "https://evil.example/x.gif"]))
    }

    func testOnlyKlipyMediaHosts() {
        let allowed = ["https://static.klipy.com/a.gif", "https://static1.klipy.com/a.gif", "https://static23.klipy.com/a/b.gif",
                       "HTTPS://STATIC2.KLIPY.COM/a.gif", "https://static.klipy.com:443/a.gif"]
        for raw in allowed {
            XCTAssertTrue(NotificationImage.isKlipyMedia(URL(string: raw)!), raw)
        }
        let refused = ["http://static.klipy.com/a.gif", "https://api.klipy.com/a.gif", "https://klipy.com/a.gif",
                       "https://staticx.klipy.com/a.gif", "https://static.klipy.com.evil.example/a.gif",
                       "https://evil.example/static.klipy.com/a.gif", "https://static.klipy.co/a.gif",
                       "https://user:pw@static.klipy.com/a.gif", "https://static.klipy.com:8443/a.gif",
                       "https://a.static.klipy.com/a.gif"]
        for raw in refused {
            XCTAssertFalse(NotificationImage.isKlipyMedia(URL(string: raw)!), raw)
        }
    }

    func testRequestsCarryTheTokenOnlyToTheService() throws {
        let photo = try XCTUnwrap(NotificationImage.request(for: .photo(id: "p-1"), base: base, token: "tok"))
        XCTAssertEqual(photo.url?.absoluteString, "https://fherrmann.com/cohabit/api/photos/p-1?size=full")
        XCTAssertEqual(photo.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertFalse(photo.httpShouldHandleCookies)
        XCTAssertLessThanOrEqual(photo.timeoutInterval, 25, "die Erweiterung hat rund 30 s")
        XCTAssertNil(NotificationImage.request(for: .photo(id: "p-1"), base: base, token: nil), "ohne Token kein Foto")

        let url = URL(string: "https://static.klipy.com/a.gif")!
        let gif = try XCTUnwrap(NotificationImage.request(for: .klipy(url), base: base, token: "tok"))
        XCTAssertEqual(gif.url, url, "die URL unveraendert")
        XCTAssertNil(gif.value(forHTTPHeaderField: "Authorization"), "der Token geht nie an KLIPY")
    }

    func testRedirects() {
        let klipy = NotificationImage.Source.klipy(URL(string: "https://static.klipy.com/a.gif")!)
        XCTAssertTrue(NotificationImage.allowsRedirect(for: klipy, to: URL(string: "https://static2.klipy.com/a.gif")))
        XCTAssertFalse(NotificationImage.allowsRedirect(for: klipy, to: URL(string: "https://evil.example/a.gif")))
        XCTAssertFalse(NotificationImage.allowsRedirect(for: .photo(id: "p"), to: URL(string: "https://fherrmann.com/x")),
                       "beim Foto ginge der Token mit")
    }

    func testFileExtensionFromBytesThenContentType() {
        let gif = Data("GIF89a......".utf8)
        XCTAssertEqual(NotificationImage.fileExtension(contentType: "image/gif", data: gif), "gif")
        XCTAssertEqual(NotificationImage.fileExtension(contentType: "image/jpeg", data: gif), "gif", "die Bytes zaehlen")
        XCTAssertEqual(NotificationImage.fileExtension(contentType: "application/octet-stream",
                                                       data: Data([0xFF, 0xD8, 0xFF, 0xDB])), "jpg")
        XCTAssertEqual(NotificationImage.fileExtension(contentType: nil, data: Data([0x89, 0x50, 0x4E, 0x47, 1])), "png")
        XCTAssertEqual(NotificationImage.fileExtension(contentType: "image/jpeg; charset=binary", data: Data([1, 2, 3])), "jpg")
        XCTAssertNil(NotificationImage.fileExtension(contentType: "text/html", data: Data("<html>".utf8)))
        XCTAssertNil(NotificationImage.fileExtension(contentType: "image/webp", data: Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBP".utf8)),
                     "WebP nimmt iOS als Anlage nicht")
        XCTAssertNil(NotificationImage.fileExtension(contentType: "image/gif", data: Data()))
        XCTAssertNil(NotificationImage.fileExtension(contentType: "image/gif",
                                                     data: Data(count: NotificationImage.maxBytes + 1)))
    }

    #if DEBUG
    func testDebugBaseGoesThroughTheAppGroupAndDefaultsToTheServer() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        XCTAssertEqual(NotificationImage.base(groupDefaults: defaults), Backend.cohabit.url)
        defaults.set("http://127.0.0.1:48792/cohabit/api", forKey: NotificationImage.debugBaseKey)
        XCTAssertEqual(NotificationImage.base(groupDefaults: defaults).absoluteString, "http://127.0.0.1:48792/cohabit/api")
    }
    #endif
}
