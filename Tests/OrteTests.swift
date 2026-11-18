import XCTest
@testable import PersonalAPI

/// Beispielantwort aus den Tests des Servers (personal-api, tests/app-beispiele).
private struct Beispiel<T: Decodable>: Decodable {
    let status: Int
    let antwort: T
}

final class OrteTests: XCTestCase {
    private func ortstag() throws -> Ortstag {
        let datei = try XCTUnwrap(Bundle(for: OrteTests.self).url(forResource: "karte-des-tages", withExtension: "json"),
                                  "Beispiel karte-des-tages.json fehlt im Testpaket")
        return try JSONDecoder().decode(Beispiel<Ortstag>.self, from: Data(contentsOf: datei)).antwort
    }

    private var berlin: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return kalender
    }

    func testKarteDesTagesVomServer() throws {
        let tag = try ortstag()
        XCTAssertEqual(tag.tag, "2026-03-14")
        XCTAssertEqual(tag.aufenthalte.count, 4)
        XCTAssertEqual(tag.routen.count, 3)
        XCTAssertEqual(tag.routen[1].start, "Ort 3")
        XCTAssertEqual(tag.routen[1].dauerMin, 11)
        XCTAssertEqual(tag.routen[1].streckeKm, 1.6)
        XCTAssertEqual(tag.aufenthalte[0].minuten, 657)
    }

    /// Orte und Fahrten wechseln sich ab, nach der Uhrzeit.
    func testAblaufNachUhrzeit() throws {
        let namen = try ortstag().ablauf.map { schritt -> String in
            switch schritt {
            case .ort(let aufenthalt): return aufenthalt.ort
            case .fahrt(let fahrt): return "\(fahrt.start)→\(fahrt.ziel)"
            }
        }
        XCTAssertEqual(namen, ["Zuhause", "Zuhause→Ort 3", "Ort 3", "Ort 3→Ort 4", "Ort 4", "Ort 4→Zuhause", "Zuhause"])
    }

    func testLueckeIstKeinOrt() {
        let tag = Ortstag(tag: "2026-03-14", aufenthalte: [
            .init(ort: "Zuhause", beginn: "2026-03-14T06:00:00Z", ende: "2026-03-14T07:00:00Z", minuten: 60),
            .init(ort: "Lücke", beginn: "2026-03-14T08:00:00Z", ende: "2026-03-14T09:00:00Z", minuten: 60, luecke: true),
        ], routen: [])
        XCTAssertEqual(tag.ablauf.count, 1)
    }

    func testZeitpunktMitNachkommastellen() throws {
        let mit = try XCTUnwrap(Zeitpunkt.lesen("2026-03-14T09:55:49.263831Z"))
        let ohne = try XCTUnwrap(Zeitpunkt.lesen("2026-03-14T09:55:49Z"))
        XCTAssertEqual(mit, ohne)
        XCTAssertEqual(Zeitpunkt.lesen("2026-03-14T10:55:49+01:00"), ohne)
        XCTAssertNil(Zeitpunkt.lesen("kein Datum"))
    }

    func testSpanneUeberMitternacht() {
        // 20:36 am Vortag bis 10:56 (Ortszeit): „bis …“
        let bis = Zeitpunkt.spanne("2026-03-13T19:36:07Z", "2026-03-14T09:56:59Z", tag: "2026-03-14", kalender: berlin)
        XCTAssertTrue(bis.hasPrefix("bis "), bis)
        let ab = Zeitpunkt.spanne("2026-03-14T12:07:22Z", "2026-03-15T16:00:00Z", tag: "2026-03-14", kalender: berlin)
        XCTAssertTrue(ab.hasPrefix("ab "), ab)
        let mitte = Zeitpunkt.spanne("2026-03-14T09:00:00Z", "2026-03-14T10:00:00Z", tag: "2026-03-14", kalender: berlin)
        XCTAssertTrue(mitte.contains("–"), mitte)
        XCTAssertEqual(Zeitpunkt.spanne("2026-03-13T09:00:00Z", "2026-03-15T10:00:00Z", tag: "2026-03-14", kalender: berlin),
                       "ganzer Tag")
    }

    func testTageBlaettern() {
        XCTAssertEqual(Kalendertag.verschoben("2026-03-01", um: -1), "2026-02-28")
        XCTAssertEqual(Kalendertag.verschoben("2026-12-31", um: 1), "2027-01-01")
        let heute = Kalendertag.heute(jetzt: Date(timeIntervalSince1970: 1_773_559_800))  // 15. März 2026
        XCTAssertEqual(Kalendertag.name(heute, heute: heute), "Heute")
        XCTAssertEqual(Kalendertag.name(Kalendertag.verschoben(heute, um: -1), heute: heute), "Gestern")
        XCTAssertNotEqual(Kalendertag.name(Kalendertag.verschoben(heute, um: -2), heute: heute), "Gestern")
    }

    func testDemoHatAblauf() {
        let demo = Ortstag.demo(tag: "2026-03-14")
        XCTAssertEqual(demo.ablauf.count, 7)
        XCTAssertNotNil(demo.ablauf.first?.beginn)
    }

    /// Die Karte blendet die Navigation des Dashboards aus; die Namen müssen zu navigation.js des Servers passen.
    func testKarteBlendetDashboardNavigationAus() {
        for teil in ["#kopf", "nav.leiste", "#blatt-mehr"] {
            XCTAssertTrue(Kartenfenster.einbetten.contains(teil), teil)
        }
    }
}
