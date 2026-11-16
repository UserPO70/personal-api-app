import XCTest
@testable import PersonalAPI

/// Beispielantwort aus den Tests des Servers (personal-api, tests/app-beispiele).
private struct Beispiel<T: Decodable>: Decodable {
    let status: Int
    let antwort: T
}

final class AuswertungTests: XCTestCase {
    private func beispiel<T: Decodable>(_ name: String, _ typ: T.Type) throws -> T {
        let datei = try XCTUnwrap(Bundle(for: AuswertungTests.self).url(forResource: name, withExtension: "json"),
                                  "Beispiel \(name).json fehlt im Testpaket")
        return try JSONDecoder().decode(Beispiel<T>.self, from: Data(contentsOf: datei)).antwort
    }

    func testVerlaufVomServer() throws {
        let verlauf = try beispiel("verlauf", Tagesverlauf.self)
        XCTAssertEqual(verlauf.bis, "2026-03-14")
        XCTAssertEqual(verlauf.tage.count, 7)
        let letzter = try XCTUnwrap(verlauf.tage.last)
        XCTAssertEqual(Kennzahl.schritte.wert(letzter), 9151)
        XCTAssertEqual(Kennzahl.stockwerke.wert(letzter), 16)
        XCTAssertEqual(Kennzahl.schlaf.wert(letzter), 580)
        // Ein Tag ohne PC-Daten ist „keine Daten“, nicht 0 Minuten.
        XCTAssertNil(Kennzahl.pcZeit.wert(letzter))
        XCTAssertEqual(Kennzahl.pcZeit.wert(verlauf.tage[0]), 74)
    }

    func testTrendUndLinie() throws {
        let verlauf = try beispiel("verlauf", Tagesverlauf.self)
        let text = try XCTUnwrap(verlauf.trend(.schritte)?.vergleich?.text)
        XCTAssertTrue(text.hasPrefix("Schritte: letzte 4 Wochen"))
        XCTAssertNil(verlauf.trend(.strecke), "Strecke hat beim Server keinen Trend")
        let linie = verlauf.linie(.schritte)
        XCTAssertEqual(linie.count, 7)
        XCTAssertEqual(Set(linie.map(\.stueck)), [0])
        XCTAssertEqual(linie.first?.tag, "2026-03-08")
        XCTAssertTrue(verlauf.linie(.strecke).isEmpty)
    }

    func testLinieSetztBeiLueckenAus() {
        let tage = (1...6).map { Tagesverlauf.Tag(tag: "2026-03-0\($0)", schritte: 1000) }
        let trend = Tagesverlauf.Trend(schluessel: "schritte", gleitend: [nil, 5, 6, nil, nil, 7], vergleich: nil)
        let verlauf = Tagesverlauf(bis: "2026-03-06", tage: tage, trends: .init(kennzahlen: [trend]))
        let linie = verlauf.linie(.schritte)
        XCTAssertEqual(linie.map(\.tag), ["2026-03-02", "2026-03-03", "2026-03-06"])
        XCTAssertEqual(linie.map(\.stueck), [0, 0, 1])
    }

    func testSchnittNurUeberTageMitDaten() {
        let tage = [
            Tagesverlauf.Tag(tag: "2026-03-01", schritte: 4000),
            Tagesverlauf.Tag(tag: "2026-03-02"),
            Tagesverlauf.Tag(tag: "2026-03-03", schritte: 6000),
        ]
        let verlauf = Tagesverlauf(bis: "2026-03-03", tage: tage, trends: nil)
        let schnitt = verlauf.schnitt(.schritte)
        XCTAssertEqual(schnitt?.wert, 5000)
        XCTAssertEqual(schnitt?.tage, 2)
        XCTAssertNil(verlauf.schnitt(.schlaf))
        XCTAssertEqual(Kennzahl.schritte.schnittText((wert: 5000, tage: 2)), "Schritte: Ø 5.000 pro Tag an 2 Tagen mit Daten.")
        XCTAssertEqual(Kennzahl.gehtempo.schnittText((wert: 4.84, tage: 1)), "Gehtempo: Ø 4,8 km/h an 1 Tag mit Daten.")
    }

    func testAchse() {
        let tage = [
            Tagesverlauf.Tag(tag: "2026-03-01", schritte: 4000, gehtempo: 4.0),
            Tagesverlauf.Tag(tag: "2026-03-02", schritte: 6000, gehtempo: 5.0),
        ]
        let verlauf = Tagesverlauf(bis: "2026-03-02", tage: tage, trends: nil)
        XCTAssertEqual(verlauf.achse(.schritte).lowerBound, 0)
        XCTAssertEqual(verlauf.achse(.schritte).upperBound, 6300, accuracy: 0.001)
        XCTAssertEqual(verlauf.achse(.gehtempo), 3.75...5.25)
        XCTAssertEqual(verlauf.achse(.schlaf), 0...1)
    }

    func testTexte() {
        XCTAssertEqual(Kennzahl.schlaf.text(430), "7 h 10 min")
        XCTAssertEqual(Kennzahl.strecke.text(6.54), "6,5 km")
        XCTAssertEqual(Kennzahl.schrittlaenge.text(72.6), "73 cm")
        XCTAssertEqual(Kennzahl.schlaf.imDiagramm(90), 1.5)
        XCTAssertEqual(Kennzahl.schritte.imDiagramm(90), 90)
    }

    func testPcKategorienVomServer() throws {
        let pc = try beispiel("pc-kategorien", PcKategorien.self)
        XCTAssertEqual(pc.gesamtMinuten, 661)
        XCTAssertEqual(pc.kategorien.count, 8)
        XCTAssertEqual(pc.kategorien.first?.name, "Programmieren")
        XCTAssertEqual(pc.kategorien.first?.anteil, 37)
        XCTAssertEqual(pc.geraete.map(\.name), ["pc-linux", "pc-windows"])
        XCTAssertEqual(pc.spiele.first?.tage, 1)
    }

    func testDemoHatFuerJedenTagEinenEintrag() {
        let demo = Tagesverlauf.demo(tage: 30)
        XCTAssertEqual(demo.tage.count, 30)
        XCTAssertEqual(Set(demo.tage.map(\.tag)).count, 30)
        XCTAssertNotNil(demo.schnitt(.pcZeit))
        XCTAssertFalse(demo.linie(.schritte).isEmpty)
    }
}
