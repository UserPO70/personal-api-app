import XCTest
@testable import PersonalAPI

/// Beispielantwort aus den Tests des Servers (personal-api, tests/app-beispiele).
private struct Beispiel<T: Decodable>: Decodable {
    let status: Int
    let antwort: T
}

final class RueckblickTests: XCTestCase {
    private func beispiel(_ name: String) throws -> Rueckblick {
        let datei = try XCTUnwrap(Bundle(for: RueckblickTests.self).url(forResource: name, withExtension: "json"),
                                  "Beispiel \(name).json fehlt im Testpaket")
        return try JSONDecoder().decode(Beispiel<Rueckblick>.self, from: Data(contentsOf: datei)).antwort
    }

    func testWocheVomServer() throws {
        let woche = try beispiel("rueckblick-woche")
        XCTAssertEqual(woche.art, "woche")
        XCTAssertEqual(woche.tageAusgewertet, 7)
        XCTAssertFalse(woche.laeuftNoch)
        XCTAssertEqual(woche.vorperiode, "Vorwoche")
        XCTAssertEqual(woche.titel, "KW 11 · 9.–15. März 2026")
        XCTAssertEqual(woche.kennzahl("schritte")?.jetzt.schnitt, 6793.6)
        XCTAssertEqual(woche.kennzahl("schritte")?.vergleich?.prozent, -23)
        XCTAssertEqual(woche.mitDaten(Rueckblick.gesundheit).map(\.schluessel), Rueckblick.gesundheit)
        XCTAssertNil(woche.kennzahl("gewicht_kg")?.jetzt.summe, "Gewicht ist ein Mittel, keine Summe")
        XCTAssertEqual(try XCTUnwrap(woche.gewicht.veraenderung?.kg), -0.95, accuracy: 1e-9)
        XCTAssertEqual(woche.jetzt.fahrten.anzahl, 20)
        XCTAssertEqual(woche.jetzt.fahrten.haeufigste.first?.strecke, "Zuhause → Ort 1")
        XCTAssertEqual(woche.jetzt.orte.first?.name, "Zuhause")
        XCTAssertEqual(woche.pc.kategorien.first?.name, "Programmieren")
        XCTAssertEqual(woche.essen.fenster.jetzt.erste, "07:35")
        XCTAssertEqual(woche.essen.fenster.vorher.letzte, "19:09")
        let ziel = try XCTUnwrap(woche.essen.ziel)
        XCTAssertEqual(ziel.zielbereichProzent, 10)
        XCTAssertEqual(ziel.jetzt.tageImZielbereich, 2)
        XCTAssertEqual(ziel.jetzt.tageVollstaendig, 5)
        XCTAssertEqual(ziel.vorher.abweichungSchnittKcal, -217)
        XCTAssertFalse(woche.leer)
    }

    func testLaufenderMonatVomServer() throws {
        let monat = try beispiel("rueckblick-monat")
        XCTAssertTrue(monat.laeuftNoch)
        XCTAssertEqual(monat.tageAusgewertet, 15)
        XCTAssertEqual(monat.tageGesamt, 31)
        XCTAssertEqual(monat.vorperiode, "Vormonat")
        XCTAssertEqual(monat.titel, "März 2026")
        XCTAssertEqual(monat.zurueck, "2026-02-01")
        XCTAssertEqual(monat.weiter, "2026-04-01")
    }

    /// In die Zukunft blättert der Rückblick nicht.
    func testWeiterNurBisHeute() throws {
        let woche = try beispiel("rueckblick-woche")
        XCTAssertFalse(woche.weiterMoeglich(heute: "2026-03-15"))
        XCTAssertTrue(woche.weiterMoeglich(heute: "2026-03-16"))
    }

    func testWerteJeEinheit() {
        XCTAssertEqual(Rueckblicktext.wert(6793.6, schluessel: "schritte"), "6.794")
        XCTAssertEqual(Rueckblicktext.wert(5.78, schluessel: "strecke_km"), "5,8 km")
        XCTAssertEqual(Rueckblicktext.wert(421, schluessel: "schlaf_minuten"), "7 h 1 min")
        XCTAssertEqual(Rueckblicktext.wert(82.7, schluessel: "gewicht_kg"), "82,7 kg")
        XCTAssertEqual(Rueckblicktext.wert(1913.4, schluessel: "kcal"), "1.913 kcal")
        XCTAssertEqual(Rueckblicktext.wert(6104.3, schluessel: "internet_mb"), "6,1 GB")
        XCTAssertEqual(Rueckblicktext.wert(512, schluessel: "internet_mb"), "512 MB")
        XCTAssertEqual(Rueckblicktext.wert(2.9, schluessel: "fahrten"), "2,9")
    }

    func testVergleichMitDerVorperiode() {
        XCTAssertEqual(Rueckblicktext.vergleich(.init(differenz: -2005.1, prozent: -23), schluessel: "schritte"), "↓ 23 %")
        XCTAssertEqual(Rueckblicktext.vergleich(.init(differenz: 229, prozent: 14), schluessel: "kcal"), "↑ 14 %")
        XCTAssertEqual(Rueckblicktext.vergleich(.init(differenz: -0.3, prozent: 0), schluessel: "schrittlaenge_cm"), "gleich")
        // Vorperiode 0: kein Prozentwert, dann der Unterschied in der Einheit.
        XCTAssertEqual(Rueckblicktext.vergleich(.init(differenz: 2, prozent: nil), schluessel: "fahrten"), "↑ 2,0")
        XCTAssertNil(Rueckblicktext.vergleich(nil, schluessel: "schritte"))
        XCTAssertEqual(Rueckblicktext.vorher(.init(summe: nil, schnitt: nil, tage: 0), schluessel: "schritte",
                                             vorperiode: "Vorwoche"), "Vorwoche: keine Daten")
        XCTAssertEqual(Rueckblicktext.vorher(.init(summe: 61591, schnitt: 8798.7, tage: 7), schluessel: "schritte",
                                             vorperiode: "Vorwoche"), "Vorwoche Ø 8.799")
        XCTAssertEqual(Rueckblicktext.mitVorzeichen(12, einheit: "kcal"), "+12 kcal")
        XCTAssertEqual(Rueckblicktext.mitVorzeichen(-1217, einheit: "kcal"), "−1.217 kcal")
        XCTAssertEqual(Rueckblicktext.mitVorzeichen(0.2, einheit: "kcal"), "±0 kcal")
    }

    func testWocheUeberDenMonatswechsel() {
        let titel = Rueckblicktext.zeitraum(art: "woche", von: "2026-03-30", bis: "2026-04-05")
        XCTAssertEqual(titel, "KW 14 · 30. März – 5. April 2026")
    }

    /// Der Demo-Modus hat Daten, und was die App sich merkt, kommt unverändert zurück.
    func testDemoUndMerken() throws {
        let demo = Rueckblick.demo(art: "woche", heute: "2026-03-15")
        XCTAssertEqual(demo.von, "2026-03-09")
        XCTAssertFalse(demo.leer)
        XCTAssertNotNil(demo.essen.ziel)
        let zurueck = try JSONDecoder().decode(Rueckblick.self, from: JSONEncoder().encode(demo))
        XCTAssertEqual(zurueck, demo)
    }
}
