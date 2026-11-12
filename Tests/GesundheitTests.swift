import XCTest
@testable import PersonalAPI

final class GesundheitTests: XCTestCase {
    /// 2026-03-15T07:30:00Z
    private let jetzt = Date(timeIntervalSince1970: 1_773_559_800)

    func testZeitenLesenUndSchreiben() {
        XCTAssertEqual(Gesundheitspaket.zeit(jetzt), "2026-03-15T07:30:00Z")
        XCTAssertEqual(Gesundheitspaket.zeitLesen("2026-03-15T07:30:00.545226Z"), jetzt)
        XCTAssertEqual(Gesundheitspaket.zeitLesen("2026-03-15T07:30:00Z"), jetzt)
        XCTAssertNil(Gesundheitspaket.zeitLesen(nil))
        XCTAssertNil(Gesundheitspaket.zeitLesen("gestern"))
    }

    func testStartgrenzeOhneDatenAmServer() {
        let grenze = Gesundheitspaket.startgrenze(letzter: nil, jetzt: jetzt)
        XCTAssertEqual(Gesundheitspaket.zeit(grenze), "2026-02-13T07:00:00Z")
    }

    func testStartgrenzeNachDemKurzbefehl() {
        // Der Kurzbefehl hat zuletzt die Stunde ab 05:00 geliefert: Dort macht die App weiter.
        let letzter = jetzt.addingTimeInterval(-2.5 * 3600)
        XCTAssertEqual(Gesundheitspaket.zeit(Gesundheitspaket.startgrenze(letzter: letzter, jetzt: jetzt)),
                       "2026-03-15T05:00:00Z")
        // Uralte Daten am Server: trotzdem höchstens 30 Tage zurück.
        let alt = jetzt.addingTimeInterval(-400 * 86400)
        XCTAssertEqual(Gesundheitspaket.zeit(Gesundheitspaket.startgrenze(letzter: alt, jetzt: jetzt)),
                       "2026-02-13T07:00:00Z")
        // Eine Zeit in der Zukunft schiebt den Anfang nicht hinter jetzt.
        let zukunft = jetzt.addingTimeInterval(5 * 3600)
        XCTAssertEqual(Gesundheitspaket.zeit(Gesundheitspaket.startgrenze(letzter: zukunft, jetzt: jetzt)),
                       "2026-03-15T07:00:00Z")
    }

    func testBeginnJeSendung() {
        let grenze = jetzt.addingTimeInterval(-10 * 86400)
        // Erste Sendung: alles ab der Startgrenze.
        XCTAssertEqual(Gesundheitspaket.beginn(startgrenze: grenze, ersteFertig: false, jetzt: jetzt), grenze)
        // Danach: die letzten 48 Stunden, auf die volle Stunde.
        XCTAssertEqual(Gesundheitspaket.zeit(Gesundheitspaket.beginn(startgrenze: grenze, ersteFertig: true, jetzt: jetzt)),
                       "2026-03-13T07:00:00Z")
        // Nie vor der Startgrenze, auch wenn sie jünger als 48 Stunden ist.
        let frisch = jetzt.addingTimeInterval(-3600)
        XCTAssertEqual(Gesundheitspaket.beginn(startgrenze: frisch, ersteFertig: true, jetzt: jetzt), frisch)
    }

    func testSendungWieDerServerSieErwartet() throws {
        let stunde = Gesundheitspaket.volleStunde(jetzt)
        let schritte = [Probe(wert: 812.0, start: stunde.addingTimeInterval(-3600), ende: stunde),
                        Probe(wert: 40.0, start: stunde, ende: stunde.addingTimeInterval(3600))]
        let schlaf = [Probe(wert: Gesundheitspaket.schlafphase(3), start: stunde.addingTimeInterval(-8 * 3600),
                            ende: stunde.addingTimeInterval(-7 * 3600))]
        let daten = try Gesundheitspaket.koerper([
            "schritte": Gesundheitspaket.block(schritte, einheit: nil),
            "strecke": Gesundheitspaket.block([Probe(wert: 612.5, start: stunde, ende: stunde.addingTimeInterval(3600))], einheit: "m"),
            "schlaf": Gesundheitspaket.block(schlaf, einheit: nil),
        ])
        let inhalt = try XCTUnwrap(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        XCTAssertEqual(inhalt["geraet"] as? String, "iphone")
        let block = try XCTUnwrap(inhalt["schritte"] as? [String: Any])
        XCTAssertEqual(block["werte"] as? [Double], [812, 40])
        XCTAssertEqual(block["start"] as? [String], ["2026-03-15T06:00:00Z", "2026-03-15T07:00:00Z"])
        XCTAssertEqual(block["ende"] as? [String], ["2026-03-15T07:00:00Z", "2026-03-15T08:00:00Z"])
        XCTAssertNil(block["einheit"])
        XCTAssertEqual((inhalt["strecke"] as? [String: Any])?["einheit"] as? String, "m")
        XCTAssertEqual((inhalt["schlaf"] as? [String: Any])?["werte"] as? [String], ["Kern"])
    }

    func testSchlafphasen() {
        XCTAssertEqual((0...5).map(Gesundheitspaket.schlafphase),
                       ["Im Bett", "Schlafend", "Wach", "Kern", "Tief", "REM"])
    }
}
