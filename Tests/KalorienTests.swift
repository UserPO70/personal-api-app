import XCTest
@testable import PersonalAPI

/// Beispielantwort aus den Tests des Servers (personal-api, tests/app-beispiele).
private struct Beispiel<T: Decodable>: Decodable {
    let status: Int
    let antwort: T
}

final class KalorienTests: XCTestCase {
    private func beispiel<T: Decodable>(_ name: String, _ typ: T.Type) throws -> Beispiel<T> {
        let datei = try XCTUnwrap(Bundle(for: KalorienTests.self).url(forResource: name, withExtension: "json"),
                                  "Beispiel \(name).json fehlt im Testpaket")
        return try JSONDecoder().decode(Beispiel<T>.self, from: Data(contentsOf: datei))
    }

    func testStandOhneAngaben() throws {
        let leer = try beispiel("kalorien-profil-leer", Kalorienstand.self).antwort
        XCTAssertNil(leer.angaben)
        XCTAssertNil(leer.rechnung)
        XCTAssertNil(leer.ziel)
        XCTAssertEqual(leer.stufen.map(\.stufe), ["wenig", "leicht", "mittel", "hoch", "sehr_hoch"])
        XCTAssertNotNil(leer.grund)
    }

    func testStandNachDemSpeichern() throws {
        let stand = try beispiel("kalorien-speichern", Kalorienstand.self).antwort
        XCTAssertEqual(stand.angaben?.groesse, 180)
        XCTAssertEqual(stand.angaben?.geburtsjahr, 1990)
        XCTAssertEqual(stand.angaben?.kgProWoche, 0.5)
        XCTAssertNil(stand.angaben?.eigenesZiel)
        XCTAssertEqual(stand.rechnung?.grundumsatz, 1777)
        XCTAssertEqual(stand.rechnung?.bedarf, 2443)
        XCTAssertEqual(stand.rechnung?.ziel, 1893)
        XCTAssertEqual(stand.rechnung?.rechenweg.count, 3)
        XCTAssertEqual(stand.rechnung?.grenzen, [])
        XCTAssertEqual(stand.ziel?.kcal, 1893)
        XCTAssertEqual(stand.ziel?.quelle, "rechnung")
        XCTAssertEqual(stand.ziel?.giltAb, "2026-03-15")
        XCTAssertEqual(stand.abweichung, 0)
        XCTAssertEqual(stand.stufen.first { $0.stufe == "leicht" }?.name, "Leicht")

        // Das Formular zeigt die gespeicherten Angaben wieder so an, wie man sie eintippt.
        let eingabe = Kalorieneingabe(try XCTUnwrap(stand.angaben))
        XCTAssertEqual(eingabe.groesse, "180")
        XCTAssertEqual(eingabe.geburtsjahr, "1990")
        XCTAssertEqual(eingabe.ziel, "abnehmen")
        XCTAssertEqual(eingabe.tempo, 0.5)
        XCTAssertEqual(eingabe.eigenesZiel, "")
    }

    func testVerlaufLesen() throws {
        let verlauf = try beispiel("kalorien-verlauf", Kalorienverlauf.self).antwort
        XCTAssertEqual(verlauf.tage.count, 7)
        XCTAssertEqual(verlauf.tage.first?.kcal, 2051)
        XCTAssertNil(verlauf.tage.first?.ziel)              // das Ziel galt an dem Tag noch nicht
        XCTAssertEqual(verlauf.tage.last?.ziel, 1893)
        XCTAssertEqual(verlauf.wochenmittel?.kcal, 1871)
        XCTAssertEqual(verlauf.gegenprobe?.bedarfGeschaetzt, 2268)
        XCTAssertEqual(verlauf.gegenprobe?.bedarfGerechnet, 2443)
        XCTAssertEqual(verlauf.gegenprobe?.abweichungProzent, -7)
        XCTAssertNil(verlauf.gegenprobe?.hinweis)
        XCTAssertEqual(verlauf.achse, 0...2500)             // größter Wert 2174, mit Luft auf volle 500
    }

    func testEingabeAlsAnfrage() {
        var eingabe = Kalorieneingabe()
        eingabe.groesse = " 178,5 "
        eingabe.geburtsjahr = "1990"
        eingabe.geschlecht = "w"
        eingabe.aktivitaet = "mittel"
        XCTAssertNil(eingabe.fehler(jahr: 2026))
        // Halten: kein Tempo, kein eigenes Ziel.
        XCTAssertEqual(eingabe.json, ["groesse_cm": "178,5", "geburtsjahr": "1990", "geschlecht": "w",
                                      "aktivitaet": "mittel", "ziel": "halten"])
        eingabe.ziel = "abnehmen"
        eingabe.tempo = 0.75
        eingabe.eigenesZiel = "2000"
        XCTAssertEqual(eingabe.json["kg_pro_woche"], "0.75")
        XCTAssertEqual(eingabe.json["eigenes_ziel_kcal"], "2000")
        XCTAssertEqual(Kalorieneingabe.tempi.max(), 1)      // mehr als 1 kg je Woche lässt sich nicht wählen
    }

    func testEingabeWirdVorDemSendenGeprueft() {
        var eingabe = Kalorieneingabe()
        XCTAssertNotNil(eingabe.fehler(jahr: 2026))         // leer
        eingabe.groesse = "178"
        XCTAssertNotNil(eingabe.fehler(jahr: 2026))         // Geburtsjahr fehlt
        eingabe.geburtsjahr = "2020"
        XCTAssertNotNil(eingabe.fehler(jahr: 2026))         // jünger als 14
        eingabe.geburtsjahr = "1990"
        XCTAssertNil(eingabe.fehler(jahr: 2026))
        eingabe.groesse = "1,78"
        XCTAssertNotNil(eingabe.fehler(jahr: 2026))         // Meter statt Zentimeter
        eingabe.groesse = "178"
        eingabe.eigenesZiel = "300"
        XCTAssertNotNil(eingabe.fehler(jahr: 2026))
        eingabe.eigenesZiel = "viel"
        XCTAssertNotNil(eingabe.fehler(jahr: 2026))
    }

    func testOffenOhneWertung() {
        XCTAssertEqual(Kalorientext.offen(gegessen: 1200.5, ziel: 1889), "noch 689 kcal offen")
        XCTAssertEqual(Kalorientext.offen(gegessen: nil, ziel: 1889), "noch 1889 kcal offen")
        XCTAssertEqual(Kalorientext.offen(gegessen: 2000, ziel: 1889), "111 kcal über dem Ziel")
        XCTAssertEqual(Kalorientext.offen(gegessen: 1889, ziel: 1889), "Ziel erreicht")
        XCTAssertEqual(Kalorientext.anteil(gegessen: 944.5, ziel: 1889), 0.5)
        XCTAssertEqual(Kalorientext.anteil(gegessen: 3000, ziel: 1889), 1)
        XCTAssertEqual(Kalorientext.anteil(gegessen: nil, ziel: 1889), 0)
        XCTAssertEqual(Kalorientext.tempo(0.5), "0,5 kg je Woche")
        XCTAssertEqual(Kalorientext.tempo(1), "1 kg je Woche")
    }
}
