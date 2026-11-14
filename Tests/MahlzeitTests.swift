import XCTest
@testable import PersonalAPI

/// Beispielantwort aus den Tests des Servers (personal-api, tests/app-beispiele).
private struct Beispiel<T: Decodable>: Decodable {
    let status: Int
    let antwort: T
}

final class MahlzeitTests: XCTestCase {
    private func beispiel<T: Decodable>(_ name: String, _ typ: T.Type) throws -> T {
        let datei = try XCTUnwrap(Bundle(for: MahlzeitTests.self).url(forResource: name, withExtension: "json"),
                                  "Beispiel \(name).json fehlt im Testpaket")
        return try JSONDecoder().decode(Beispiel<T>.self, from: Data(contentsOf: datei)).antwort
    }

    private func mahlzeit(_ nummer: Int) throws -> Mahlzeit {
        try XCTUnwrap(beispiel("essen-tag", Essenstag.self).mahlzeiten.first { $0.id == nummer })
    }

    // MARK: Details

    func testEinzelheitenEinesFotos() throws {
        let foto = try mahlzeit(178)
        XCTAssertEqual(foto.fotos, [1])
        XCTAssertEqual(foto.daten?.sicherheit, "mittel")
        XCTAssertEqual(foto.daten?.hinweis, "Portion auf normalem Teller geschätzt")
        XCTAssertEqual(foto.daten?.gewogen, 350)
        XCTAssertEqual(foto.herkunft, "Foto, Menge gewogen")
        XCTAssertFalse(foto.geschaetzt)                     // gewogen zählt als fest
        XCTAssertEqual(foto.aenderbar, true)
        XCTAssertEqual(foto.artGeschaetzt, true)
        let teile = try XCTUnwrap(foto.bestandteile)
        XCTAssertEqual(teile.map(\.mengeText), ["250 g", "150 ml"])
        XCTAssertEqual(teile[0].eiweiss, 14)
        XCTAssertEqual(teile[0].kohlenhydrate, 77)
        XCTAssertEqual(teile[1].fett, 3.6)
    }

    func testHerkunftInWorten() throws {
        XCTAssertEqual(try mahlzeit(177).herkunft, "Barcode, Nährwerte von der Packung")
        XCTAssertEqual(try mahlzeit(177).fotos, [])
        XCTAssertNil(try mahlzeit(177).daten?.sicherheit)
        XCTAssertEqual(try mahlzeit(180).herkunft, "von Hand eingetragen oder Favorit")

        var foto = try mahlzeit(178)
        foto.daten?.gewogen = nil
        XCTAssertEqual(foto.herkunft, "Foto, von Claude geschätzt")
        XCTAssertTrue(foto.geschaetzt)
        foto.korrigiert = true
        XCTAssertEqual(foto.herkunft, "von Hand korrigiert")
        XCTAssertFalse(foto.geschaetzt)                     // wer korrigiert, hat die Zahlen geprüft
    }

    func testEinschaetzungVertraegtUnerwartetes() throws {
        // Je nach Quelle stehen in „daten“ ganz andere Dinge; daran darf der ganze Tag nicht scheitern.
        let roh = #"{"id": 1, "daten": {"sicherheit": 3, "hinweis": ["a"], "gewogen_g": "viel", "sonstiges": {"x": 1}}}"#
        let mahlzeit = try JSONDecoder().decode(Mahlzeit.self, from: Data(roh.utf8))
        XCTAssertEqual(mahlzeit.daten, Mahlzeit.Einschaetzung())
        XCTAssertEqual(mahlzeit.titel, "Mahlzeit")
    }

    // MARK: Ändern

    func testKorrekturAlsAnfrage() throws {
        var korrektur = Mahlzeitkorrektur(try mahlzeit(178))
        XCTAssertEqual(korrektur.zeilen.map(\.lebensmittel), ["Spaghetti", "Tomatensoße"])
        XCTAssertEqual(korrektur.zeilen[0].menge, "250")
        XCTAssertEqual(korrektur.zeilen[0].kcal, "395")
        XCTAssertEqual(korrektur.zeilen[1].fett, "3,6")
        XCTAssertEqual(korrektur.notiz, "große Portion")
        XCTAssertNil(korrektur.fehler)
        XCTAssertEqual(korrektur.kcal, 485)

        korrektur.zeilen[1].lebensmittel = "Tomatensoße mit Hack"
        korrektur.notiz = " halbe Portion "
        let inhalt = try XCTUnwrap(JSONSerialization.jsonObject(with: korrektur.koerper()) as? [String: Any])
        XCTAssertEqual(inhalt["notiz"] as? String, "halbe Portion")
        let teile = try XCTUnwrap(inhalt["bestandteile"] as? [[String: Any]])
        XCTAssertEqual(teile.count, 2)
        XCTAssertEqual(teile[0]["lebensmittel"] as? String, "Spaghetti")
        XCTAssertEqual(teile[0]["menge"] as? Double, 250)
        XCTAssertEqual(teile[0]["einheit"] as? String, "g")
        XCTAssertEqual(teile[0]["kcal"] as? Double, 395)
        XCTAssertEqual(teile[0]["eiweiss_g"] as? Double, 14)
        XCTAssertEqual(teile[1]["lebensmittel"] as? String, "Tomatensoße mit Hack")
        XCTAssertEqual(teile[1]["fett_g"] as? Double, 3.6)
    }

    func testMengeAendernRechnetNaehrwerteMit() throws {
        var zeile = Mahlzeitkorrektur(try mahlzeit(178)).zeilen[0]   // 250 g Spaghetti, 395 kcal
        zeile.mengeAendern(auf: "125", umrechnen: true)
        XCTAssertEqual(zeile.menge, "125")
        XCTAssertEqual(zeile.kcal, "197,5")
        XCTAssertEqual(zeile.eiweiss, "7")
        XCTAssertEqual(zeile.kohlenhydrate, "38,5")

        // Ohne Umrechnen bleibt alles andere stehen.
        zeile.mengeAendern(auf: "500", umrechnen: false)
        XCTAssertEqual(zeile.menge, "500")
        XCTAssertEqual(zeile.kcal, "197,5")

        // Beim Tippen steht das Feld zwischendurch leer: Dann wird nichts verrechnet und nichts gelöscht.
        zeile.mengeAendern(auf: "", umrechnen: true)
        XCTAssertEqual(zeile.kcal, "197,5")
        zeile.mengeAendern(auf: "100", umrechnen: true)             // vorher leer: kein Verhältnis bekannt
        XCTAssertEqual(zeile.kcal, "197,5")
    }

    func testKorrekturWirdVorDemSendenGeprueft() throws {
        var korrektur = Mahlzeitkorrektur(try mahlzeit(178))
        korrektur.zeilen[0].kcal = "viel"
        XCTAssertEqual(korrektur.fehler, "Bestandteil 1: „viel“ ist keine Zahl.")
        korrektur.zeilen[0].kcal = ""                               // leer heißt: keine Angabe
        XCTAssertNil(korrektur.fehler)
        XCTAssertNil(korrektur.zeilen[0].json["kcal"])
        korrektur.zeilen[1].lebensmittel = "  "
        XCTAssertEqual(korrektur.fehler, "Bestandteil 2 hat keinen Namen.")
        korrektur.zeilen.removeAll()
        XCTAssertNotNil(korrektur.fehler)

        // Ein neuer, leerer Bestandteil ohne Menge schickt weder Menge noch Einheit.
        var neu = Bestandteilzeile()
        neu.lebensmittel = "Apfel"
        XCTAssertEqual(neu.json.keys.sorted(), ["lebensmittel"])
        XCTAssertEqual(Bestandteilzeile.zahl("0"), 0)               // 0 kcal ist eine gültige Angabe
        XCTAssertNil(Bestandteilzeile.zahl("-5"))
    }

    // MARK: Heute

    func testTagesueberblickLesen() throws {
        let heute = try beispiel("heute", Tagesueberblick.self)
        XCTAssertEqual(heute.tag, "2026-03-15")
        XCTAssertEqual(heute.uebersicht?.schritte, 2352)
        XCTAssertNil(heute.uebersicht?.schlaf)
        XCTAssertNil(heute.uebersicht?.strecke)
        XCTAssertEqual(heute.essen?.summe?.kcal, 1777)
        XCTAssertEqual(heute.essen?.ziel?.kcal, 1893)
        XCTAssertEqual(heute.essen?.ziel?.gegessen, 1777)
        XCTAssertEqual(heute.koerper?.gewicht?.kg, 81.6)

        let gestern = try beispiel("heute-anderer-tag", Tagesueberblick.self)
        XCTAssertEqual(gestern.uebersicht?.schlaf?.minuten, 580)
        XCTAssertEqual(gestern.uebersicht?.strecke, 6.54)
        XCTAssertEqual(gestern.uebersicht?.stockwerke, 16)
        XCTAssertNil(gestern.essen?.ziel)                           // an dem Tag galt noch kein Ziel
    }

    func testZahlenFuerDenUeberblick() {
        XCTAssertEqual(Dauertext.minuten(580), "9 h 40 min")
        XCTAssertEqual(Dauertext.minuten(45), "45 min")
        XCTAssertEqual(Dauertext.minuten(120), "2 h")
        XCTAssertEqual(Dauertext.kilometer(6.54), "6,5 km")
        XCTAssertEqual(Dauertext.ganzzahl(9151), "9.151")
        XCTAssertEqual(Dauertext.ganzzahl(12_005), "12.005")
        XCTAssertEqual(Dauertext.ganzzahl(812), "812")
        XCTAssertEqual(Dauertext.wartend(eintraege: 1, analysen: 0), "1 Eintrag wartet auf den Server")
        XCTAssertEqual(Dauertext.wartend(eintraege: 3, analysen: 1), "3 Einträge warten auf den Server · 1 wird geschätzt")
        XCTAssertEqual(Dauertext.wartend(eintraege: 0, analysen: 2), "2 werden geschätzt")
    }
}
