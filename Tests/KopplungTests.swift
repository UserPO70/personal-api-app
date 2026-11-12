import XCTest
@testable import PersonalAPI

final class KopplungTests: XCTestCase {
    /// Beispiel aus dem Handbuch des Servers (docs/app.md).
    func testPruefzahlWieImHandbuch() {
        let app = String(repeating: "a", count: 64)
        let server = String(repeating: "b", count: 64)
        XCTAssertEqual(Pruefzahl.berechnen(appZufall: app, serverZufall: server), "033266")
    }

    func testZusageIstSha256DesTextes() {
        XCTAssertEqual(Pruefzahl.zusage("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testZufallIst64HexUndJedesMalAnders() {
        let eins = Pruefzahl.zufall()
        XCTAssertEqual(eins.count, 64)
        XCTAssertTrue(eins.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertNotEqual(eins, Pruefzahl.zufall())
    }

    func testEinladungMitHttps() throws {
        let abdruck = String(repeating: "ef", count: 32)
        let text = "personal-api://koppeln?v=1&adresse=https%3A%2F%2F192.168.1.20%3A8443&code=482913&fingerabdruck=\(abdruck)"
        let einladung = try XCTUnwrap(Einladung(text: text))
        XCTAssertEqual(einladung.adresse, "https://192.168.1.20:8443")
        XCTAssertEqual(einladung.code, "482913")
        XCTAssertEqual(einladung.fingerabdruck, abdruck)
        XCTAssertTrue(einladung.verschluesselt)
    }

    func testEinladungOhneHttps() throws {
        let einladung = try XCTUnwrap(Einladung(text: "personal-api://koppeln?v=1&adresse=http%3A%2F%2F192.168.1.20%3A8000&code=482913"))
        XCTAssertEqual(einladung.adresse, "http://192.168.1.20:8000")
        XCTAssertNil(einladung.fingerabdruck)
        XCTAssertFalse(einladung.verschluesselt)
    }

    func testFremdeUndKaputteCodesWerdenAbgelehnt() {
        XCTAssertNil(Einladung(text: "https://example.org/?code=1"))
        XCTAssertNil(Einladung(text: "personal-api://koppeln?v=2&adresse=http%3A%2F%2F192.168.1.20%3A8000&code=482913"))
        XCTAssertNil(Einladung(text: "personal-api://koppeln?v=1&code=482913"))
        // HTTPS ohne Fingerabdruck: Die App wüsste nicht, wem sie vertrauen soll.
        XCTAssertNil(Einladung(text: "personal-api://koppeln?v=1&adresse=https%3A%2F%2F192.168.1.20%3A8443&code=482913"))
        XCTAssertNil(Einladung(text: "personal-api://koppeln?v=1&adresse=https%3A%2F%2F192.168.1.20%3A8443&code=482913&fingerabdruck=kurz"))
    }

    func testEingabeVonHand() throws {
        let einladung = try XCTUnwrap(Einladung(adresse: " 192.168.1.20:8000/ ", code: "482 913"))
        XCTAssertEqual(einladung.adresse, "http://192.168.1.20:8000")
        XCTAssertEqual(einladung.code, "482913")
        XCTAssertNil(Einladung(adresse: "https://192.168.1.20:8443", code: "482913"))
        XCTAssertNil(Einladung(adresse: "192.168.1.20:8000", code: ""))
    }
}
