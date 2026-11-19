import CoreLocation
import XCTest
@testable import PersonalAPI

/// Beispielantwort aus den Tests des Servers (personal-api, tests/app-beispiele).
private struct Beispiel<T: Decodable>: Decodable {
    let status: Int
    let antwort: T
}

final class FahrtenbuchTests: XCTestCase {
    private func beispiel<T: Decodable>(_ name: String, _ typ: T.Type) throws -> T {
        let datei = try XCTUnwrap(Bundle(for: FahrtenbuchTests.self).url(forResource: name, withExtension: "json"),
                                  "Beispiel \(name).json fehlt im Testpaket")
        return try JSONDecoder().decode(Beispiel<T>.self, from: Data(contentsOf: datei)).antwort
    }

    /// 18.11.2026 zur angegebenen Uhrzeit (Ortszeit des Geräts, wie `Gewichtsverlauf.datum`).
    private func uhr(_ stunde: Int, _ minute: Int, tag: Int = 18) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: tag, hour: stunde, minute: minute))!
    }

    private func fahrt(_ von: Date, _ bis: Date?, laeuft: Bool = false) -> LokaleFahrt {
        LokaleFahrt(id: UUID().uuidString, beginn: von, ende: bis, meter: 5000, laeuft: laeuft)
    }

    private func server(bis: Date, fahrten: [(Date, Date)]) -> Ortstag {
        Ortstag(tag: "2026-11-18", aufenthalte: [
            Ortstag.Aufenthalt(ort: "Zuhause", beginn: Zeitpunkt.text(uhr(0, 0)), ende: Zeitpunkt.text(bis)),
        ], routen: fahrten.enumerated().map { i, zeit in
            Ortstag.Fahrt(kennung: "f\(i)", start: "Zuhause", ziel: "Arbeit",
                          abfahrt: Zeitpunkt.text(zeit.0), ankunft: Zeitpunkt.text(zeit.1))
        })
    }

    // MARK: Antworten des Servers

    func testErkannteOrteVomServer() throws {
        let orte = try beispiel("orte", [BekannterOrt].self)
        XCTAssertEqual(orte.first?.name, "Zuhause")
        XCTAssertNil(orte.first?.nameId)
        XCTAssertEqual(orte.first?.automatischerName, "Zuhause")
        XCTAssertEqual(orte.first?.benannt, true)
        XCTAssertTrue(Ortsdienst.istZuhause("Zuhause", ort: orte.first))
        let ort1 = try XCTUnwrap(Ortsdienst.ort(zu: "Ort 1", in: orte))
        XCTAssertFalse(Ortsdienst.istZuhause("Ort 1", ort: ort1))
        XCTAssertEqual(ort1.lat, 50.118, accuracy: 1e-9)
    }

    func testEigeneNamenUndAusgeblendeteVomServer() throws {
        let namen = try beispiel("ortsnamen", [Ortsname].self)
        XCTAssertEqual(namen.first?.name, "Stammplatz")
        XCTAssertEqual(namen.first?.orte, 1)
        let aus = try beispiel("orte-ausgeblendet", [AusgeblendeterOrt].self)
        XCTAssertEqual(aus.first?.id, 1)
        XCTAssertNotNil(aus.first?.erstelltAm.flatMap(Zeitpunkt.lesen))
    }

    /// Die Karte des Tages liefert die Mitte jedes Aufenthalts, damit er sich benennen lässt.
    func testAufenthaltHatMitte() throws {
        let tag = try beispiel("karte-des-tages", Ortstag.self)
        XCTAssertEqual(try XCTUnwrap(tag.aufenthalte.first?.lat), 50.09997, accuracy: 1e-9)
        XCTAssertNotNil(tag.aufenthalte.first?.lon)
    }

    /// Ein eigener Name ändert per PUT, ein neuer per POST mit der Mitte des Orts; „Kein Halt“ schickt die Bestätigung mit.
    func testJsonFuerDenServer() throws {
        let daten = try Ortsdienst.json(["name": "Bäcker", "lat": 50.1, "lon": 8.2, "bestaetigt": true])
        let zurueck = try XCTUnwrap(JSONSerialization.jsonObject(with: daten) as? [String: Any])
        XCTAssertEqual(zurueck["name"] as? String, "Bäcker")
        XCTAssertEqual(zurueck["lat"] as? Double, 50.1)
        XCTAssertEqual(zurueck["bestaetigt"] as? Bool, true)
    }

    // MARK: Namen unterwegs

    func testNaechsterBekannterOrtImUmkreis() {
        let orte = [BekannterOrt(name: "Arbeit", lat: 50.0, lon: 8.0),
                    BekannterOrt(name: "Bäcker", lat: 50.001, lon: 8.0)]   // rund 111 m nördlich
        XCTAssertEqual(Fahrtregel.ortsname(lat: 50.0002, lon: 8.0, orte: orte), "Arbeit")
        XCTAssertEqual(Fahrtregel.ortsname(lat: 50.0009, lon: 8.0, orte: orte), "Bäcker")
        XCTAssertNil(Fahrtregel.ortsname(lat: 50.003, lon: 8.0, orte: orte))      // über 150 m von beiden
        XCTAssertNil(Fahrtregel.ortsname(lat: nil, lon: 8.0, orte: orte))
        XCTAssertNil(Fahrtregel.ortsname(lat: 50.0, lon: 8.0, orte: []))
    }

    // MARK: Was der Server noch nicht kennt

    func testOhneServerdatenAlleFahrtenDesTages() {
        let fahrten = [fahrt(uhr(9, 0), uhr(9, 20)), fahrt(uhr(8, 0), uhr(8, 30)),
                       fahrt(uhr(9, 0, tag: 17), uhr(9, 30, tag: 17))]
        let offen = Fahrtregel.offen(fahrten, server: nil, tag: "2026-11-18")
        XCTAssertEqual(offen.map(\.beginn), [uhr(8, 0), uhr(9, 0)])
    }

    func testNurFahrtenNachDemStandDesServers() {
        let stand = server(bis: uhr(10, 23), fahrten: [(uhr(8, 3), uhr(8, 29))])
        let frueh = fahrt(uhr(8, 0), uhr(8, 30))      // kennt der Server schon
        let spaeter = fahrt(uhr(10, 40), uhr(11, 5))  // Punkte noch nicht angekommen
        let jetzt = fahrt(uhr(11, 30), uhr(11, 42), laeuft: true)
        let offen = Fahrtregel.offen([frueh, spaeter, jetzt], server: stand, tag: "2026-11-18")
        XCTAssertEqual(offen.map(\.id), [spaeter.id, jetzt.id])
    }

    /// Kommt eine Fahrt am Server an, verschwindet die eigene, auch wenn er sie etwas anders schneidet.
    func testFahrtDesServersErsetztDieEigene() {
        let eigene = fahrt(uhr(10, 40), uhr(11, 5))
        let stand = server(bis: uhr(10, 39), fahrten: [(uhr(10, 41), uhr(11, 4))])
        XCTAssertTrue(Fahrtregel.offen([eigene], server: stand, tag: "2026-11-18").isEmpty)
    }

    /// Hat der Server schon Punkte nach der Fahrt, hat er sie ausgewertet (auch wenn er sie nicht als Fahrt sieht).
    func testServerWeiterAlsDieFahrt() {
        let eigene = fahrt(uhr(10, 40), uhr(10, 44))
        let stand = server(bis: uhr(12, 0), fahrten: [])
        XCTAssertTrue(Fahrtregel.offen([eigene], server: stand, tag: "2026-11-18").isEmpty)
    }

    // MARK: Fahrtenbuch

    private func datei() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fahrtenbuch-\(UUID().uuidString).json")
    }

    private func ort(_ lat: Double, _ lon: Double, _ zeit: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: zeit)
    }

    @MainActor
    func testFahrtWirdMitgeschrieben() throws {
        let pfad = datei()
        defer { try? FileManager.default.removeItem(at: pfad) }
        let buch = Fahrtenbuch(datei: pfad, jetzt: uhr(8, 0))
        buch.beginnen(uhr(8, 0), ort: ort(50.0, 8.0, uhr(7, 59)))
        // Rund 1,1 km nach Norden in drei Schritten, dann Stillstand.
        buch.punkt(ort(50.004, 8.0, uhr(8, 2)), ziel: ort(50.004, 8.0, uhr(8, 2)), bewegt: uhr(8, 2))
        buch.punkt(ort(50.01, 8.0, uhr(8, 5)), ziel: ort(50.01, 8.0, uhr(8, 5)), bewegt: uhr(8, 5))
        XCTAssertEqual(buch.fahrten.last?.laeuft, true)
        buch.punkt(ort(50.01, 8.0, uhr(8, 9)), ziel: ort(50.01, 8.0, uhr(8, 5)), bewegt: uhr(8, 5))
        buch.beenden()
        let f = try XCTUnwrap(buch.fahrten.last)
        XCTAssertFalse(f.laeuft)
        XCTAssertEqual(f.meter, 1112, accuracy: 15)
        XCTAssertEqual(f.ende, uhr(8, 5))          // Ankunft = letzte Bewegung, nicht das Ende des Stillstands
        XCTAssertEqual(f.minuten ?? 0, 5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(f.startLat), 50.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(f.zielLat), 50.01, accuracy: 1e-9)
        // Bleibt nach einem Neustart der App erhalten.
        XCTAssertEqual(Fahrtenbuch(datei: pfad, jetzt: uhr(9, 0)).fahrten, buch.fahrten)
    }

    @MainActor
    func testKurzeProbeZaehltNicht() {
        let pfad = datei()
        defer { try? FileManager.default.removeItem(at: pfad) }
        let buch = Fahrtenbuch(datei: pfad, jetzt: uhr(8, 0))
        buch.beginnen(uhr(8, 0), ort: ort(50.0, 8.0, uhr(8, 0)))
        buch.punkt(ort(50.001, 8.0, uhr(8, 1)), ziel: ort(50.001, 8.0, uhr(8, 1)), bewegt: uhr(8, 1))   // rund 111 m
        buch.beenden()
        XCTAssertTrue(buch.fahrten.isEmpty)
    }

    @MainActor
    func testAlteFahrtenFallenWeg() {
        let pfad = datei()
        defer { try? FileManager.default.removeItem(at: pfad) }
        let buch = Fahrtenbuch(datei: pfad, jetzt: uhr(8, 0, tag: 10))
        buch.beginnen(uhr(8, 0, tag: 10), ort: ort(50.0, 8.0, uhr(8, 0, tag: 10)))
        buch.punkt(ort(50.01, 8.0, uhr(8, 5, tag: 10)), ziel: ort(50.01, 8.0, uhr(8, 5, tag: 10)), bewegt: uhr(8, 5, tag: 10))
        buch.beenden()
        XCTAssertEqual(buch.fahrten.count, 1)
        XCTAssertTrue(Fahrtenbuch(datei: pfad, jetzt: uhr(8, 0, tag: 14)).fahrten.isEmpty)
    }

    /// Eine vergessene, noch laufende Fahrt endet, wenn die nächste beginnt.
    @MainActor
    func testNeueFahrtSchliesstDieAlte() {
        let pfad = datei()
        defer { try? FileManager.default.removeItem(at: pfad) }
        let buch = Fahrtenbuch(datei: pfad, jetzt: uhr(8, 0))
        buch.beginnen(uhr(8, 0), ort: nil)
        buch.beginnen(uhr(12, 0), ort: nil)
        XCTAssertEqual(buch.fahrten.map(\.laeuft), [false, true])
    }
}
