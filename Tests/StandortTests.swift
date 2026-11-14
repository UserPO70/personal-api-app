import XCTest
@testable import PersonalAPI

final class StandortTests: XCTestCase {
    func testPunktWieOwnTracks() throws {
        let punkt = Standortpunkt(lat: 50.1, lon: 8.2, tst: 1_773_559_800, acc: 8, vel: 42, alt: nil, cog: 270, t: nil, m: 2)
        let daten = try Standortregel.koerper([punkt, Standortpunkt(lat: 50.2, lon: 8.3, tst: 1_773_559_810, acc: 65,
                                                                    vel: nil, alt: nil, cog: nil, t: "v", m: 1)])
        let liste = try XCTUnwrap(JSONSerialization.jsonObject(with: daten) as? [[String: Any]])
        XCTAssertEqual(liste.count, 2)
        XCTAssertEqual(liste[0]["_type"] as? String, "location")
        XCTAssertEqual(liste[0]["lat"] as? Double, 50.1)
        XCTAssertEqual(liste[0]["lon"] as? Double, 8.2)
        XCTAssertEqual(liste[0]["tst"] as? Int, 1_773_559_800)   // ganze Sekunden, sonst verwirft der Server den Punkt
        XCTAssertEqual(liste[0]["acc"] as? Int, 8)
        XCTAssertEqual(liste[0]["vel"] as? Int, 42)
        XCTAssertEqual(liste[0]["cog"] as? Int, 270)
        XCTAssertNil(liste[0]["alt"])
        XCTAssertNil(liste[0]["t"])
        XCTAssertEqual(liste[1]["t"] as? String, "v")            // Besuch: Der Server hält das nicht für eine Durchfahrt
        XCTAssertNil(liste[1]["vel"])
    }

    func testImAlltagZaehltJederGueltigePunkt() {
        XCTAssertTrue(Standortregel.aufnehmen(genauigkeit: 1200, sekundenSeitLetztem: nil, meterSeitLetztem: nil, fahrt: false))
        XCTAssertTrue(Standortregel.aufnehmen(genauigkeit: 65, sekundenSeitLetztem: 300, meterSeitLetztem: 2, fahrt: false))
        // Ungültig oder in derselben Sekunde wie der vorige.
        XCTAssertFalse(Standortregel.aufnehmen(genauigkeit: -1, sekundenSeitLetztem: 300, meterSeitLetztem: 600, fahrt: false))
        XCTAssertFalse(Standortregel.aufnehmen(genauigkeit: 10, sekundenSeitLetztem: 0.4, meterSeitLetztem: 600, fahrt: false))
    }

    func testWaehrendDerFahrtWirdAusgeduennt() {
        XCTAssertTrue(Standortregel.aufnehmen(genauigkeit: 8, sekundenSeitLetztem: nil, meterSeitLetztem: nil, fahrt: true))
        XCTAssertTrue(Standortregel.aufnehmen(genauigkeit: 8, sekundenSeitLetztem: 4, meterSeitLetztem: 60, fahrt: true))
        XCTAssertFalse(Standortregel.aufnehmen(genauigkeit: 8, sekundenSeitLetztem: 2, meterSeitLetztem: 60, fahrt: true))   // zu früh
        XCTAssertFalse(Standortregel.aufnehmen(genauigkeit: 8, sekundenSeitLetztem: 30, meterSeitLetztem: 5, fahrt: true))   // steht an der Ampel
        XCTAssertFalse(Standortregel.aufnehmen(genauigkeit: 150, sekundenSeitLetztem: 30, meterSeitLetztem: 400, fahrt: true)) // zu ungenau
    }

    func testVergesseneFahrtEndetVonSelbst() {
        XCTAssertFalse(Standortregel.fahrtZuEnde(seitBewegung: 120, seitBeginn: 3600))
        XCTAssertTrue(Standortregel.fahrtZuEnde(seitBewegung: 600, seitBeginn: 3600))        // 10 Minuten Stillstand
        XCTAssertTrue(Standortregel.fahrtZuEnde(seitBewegung: 5, seitBeginn: 8 * 3600))      // läuft schon 8 Stunden
    }

    func testTempoGemessenOderGerechnet() throws {
        // Das iPhone liefert ein Tempo und der Ort ist genau: 10 m/s sind 36 km/h.
        XCTAssertEqual(try XCTUnwrap(Standortregel.tempo(gemessen: 10, genauigkeit: 8, meter: nil, sekunden: nil)), 36, accuracy: 0.001)
        // Kein Tempo (grober Punkt aus dem Mobilfunknetz): aus zwei Punkten, 1000 m in 60 s sind 60 km/h.
        XCTAssertEqual(try XCTUnwrap(Standortregel.tempo(gemessen: -1, genauigkeit: 65, meter: 1000, sekunden: 60)), 60, accuracy: 0.001)
        // Zu nah beieinander für die Genauigkeit, zu kurz oder zu lange her: lieber keine Aussage.
        XCTAssertNil(Standortregel.tempo(gemessen: -1, genauigkeit: 800, meter: 1000, sekunden: 60))
        XCTAssertNil(Standortregel.tempo(gemessen: -1, genauigkeit: 65, meter: 200, sekunden: 30))
        XCTAssertNil(Standortregel.tempo(gemessen: -1, genauigkeit: 65, meter: 1000, sekunden: 3))
        XCTAssertNil(Standortregel.tempo(gemessen: -1, genauigkeit: 65, meter: 5000, sekunden: 7200))
        XCTAssertNil(Standortregel.tempo(gemessen: -1, genauigkeit: 65, meter: nil, sekunden: nil))
        // Ein gemessenes Tempo bei ungenauem Ort zählt nicht.
        XCTAssertNil(Standortregel.tempo(gemessen: 30, genauigkeit: 500, meter: nil, sekunden: nil))
    }

    func testFahrtenSelbstErkennen() {
        XCTAssertFalse(Standortregel.istFahrtempo(nil))
        XCTAssertFalse(Standortregel.istFahrtempo(5))       // zu Fuß
        XCTAssertFalse(Standortregel.istFahrtempo(19.9))
        XCTAssertTrue(Standortregel.istFahrtempo(20))
        XCTAssertTrue(Standortregel.istFahrtempo(130))
        XCTAssertFalse(Standortregel.istFahrtempo(900))     // Messfehler
        // Die Probe nach dem Aufbruch dauert drei Minuten, die nächste gibt es frühestens nach 15.
        XCTAssertFalse(Standortregel.probeVorbei(seitBeginn: 120))
        XCTAssertTrue(Standortregel.probeVorbei(seitBeginn: 180))
        XCTAssertFalse(Standortregel.probeErlaubt(seitLetzter: 600))
        XCTAssertTrue(Standortregel.probeErlaubt(seitLetzter: 900))
    }

    func testWartezeitNachFehlversuchen() {
        XCTAssertEqual(Standortregel.wartezeit(fehlversuche: 0), 0)
        XCTAssertEqual(Standortregel.wartezeit(fehlversuche: 1), 300)
        XCTAssertEqual(Standortregel.wartezeit(fehlversuche: 2), 600)
        XCTAssertEqual(Standortregel.wartezeit(fehlversuche: 3), 1200)
        XCTAssertEqual(Standortregel.wartezeit(fehlversuche: 4), 1800)
        XCTAssertEqual(Standortregel.wartezeit(fehlversuche: 40), 1800)
    }

    func testPufferUeberlebtAlsDatei() throws {
        let punkte = [Standortpunkt(lat: 50.1, lon: 8.2, tst: 10, acc: 8, vel: 42, alt: 120, cog: 90, t: nil, m: 2)]
        let zurueck = try JSONDecoder().decode([Standortpunkt].self, from: JSONEncoder().encode(punkte))
        XCTAssertEqual(zurueck, punkte)
    }
}
