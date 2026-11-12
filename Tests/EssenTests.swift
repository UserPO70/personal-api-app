import UIKit
import XCTest
@testable import PersonalAPI

/// Beispielantwort aus den Tests des Servers (personal-api, tests/app-beispiele).
private struct Beispiel<T: Decodable>: Decodable {
    let status: Int
    let antwort: T
}

final class EssenTests: XCTestCase {
    private func beispiel<T: Decodable>(_ name: String, _ typ: T.Type) throws -> Beispiel<T> {
        let datei = try XCTUnwrap(Bundle(for: EssenTests.self).url(forResource: name, withExtension: "json"),
                                  "Beispiel \(name).json fehlt im Testpaket")
        return try JSONDecoder().decode(Beispiel<T>.self, from: Data(contentsOf: datei))
    }

    private func eintrag(_ art: Eintrag.Art) -> Eintrag {
        Eintrag(id: "app-1", art: art, zeit: Date(timeIntervalSince1970: 1_773_559_800), titel: "Test")
    }

    private func json(_ anfrage: Anfrage) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: anfrage.koerper) as? [String: Any])
    }

    // MARK: Antworten des Servers lesen

    func testEssenstagLesen() throws {
        let tag = try beispiel("essen-tag", Essenstag.self).antwort
        XCTAssertEqual(tag.tag, "2026-03-15")
        XCTAssertEqual(tag.anzahl, 4)
        XCTAssertEqual(tag.summe?.kcal, 1549)
        XCTAssertEqual(tag.mahlzeiten.first?.uhrzeit, "08:00")
        XCTAssertEqual(tag.mahlzeiten.first?.titel, "Test-Müsli Beere (Testmarke)")
        XCTAssertEqual(tag.mahlzeiten[1].titel, "Spaghetti, Tomatensoße")
    }

    func testSendeantwortenLesen() throws {
        let foto = try beispiel("essen-foto", Sendeantwort.self)
        XCTAssertEqual(foto.status, 202)
        XCTAssertEqual(foto.antwort.id, 1)
        XCTAssertEqual(foto.antwort.status, "wartet")
        XCTAssertEqual(try beispiel("essen-foto-doppelt", Sendeantwort.self).antwort.doppelt, true)
        XCTAssertEqual(try beispiel("essen-text", Sendeantwort.self).antwort.id, 3)
        XCTAssertEqual(try beispiel("essen-barcode", Sendeantwort.self).antwort.id, 177)
        XCTAssertEqual(try beispiel("favorit-nach-name", Sendeantwort.self).antwort.id, 179)
    }

    func testAuftragsstandLesen() throws {
        XCTAssertEqual(try beispiel("essen-foto-stand-wartet", Auftragsstand.self).antwort.status, "wartet")
        XCTAssertEqual(try beispiel("essen-foto-stand-fertig", Auftragsstand.self).antwort.status, "fertig")
    }

    func testBarcodeUndFavoritenLesen() throws {
        let auskunft = try beispiel("essen-barcode-nachschlagen", BarcodeAuskunft.self).antwort
        XCTAssertTrue(auskunft.gefunden)
        XCTAssertEqual(auskunft.produkt?.bezeichnung, "Test-Müsli Beere (Testmarke)")
        XCTAssertEqual(auskunft.produkt?.je100?.kcal, 380)
        XCTAssertEqual(auskunft.produkt?.portion, 50)
        let favoriten = try beispiel("favoriten", Favoritenliste.self).antwort.favoriten
        XCTAssertEqual(favoriten.map(\.name), ["Müsli"])
        XCTAssertEqual(favoriten.first?.summe?.kcal, 304)
    }

    // MARK: Anfragen bauen

    func testBarcodeAnfrage() throws {
        var scan = eintrag(.barcode)
        scan.barcode = "4000000000013"
        scan.menge = 80
        scan.einheit = "g"
        scan.gehoertZu = "app-0"
        let anfrage = try scan.anfrage(bild: nil)
        XCTAssertEqual(anfrage.pfad, "/api/essen/barcode")
        XCTAssertEqual(anfrage.typ, "application/json")
        let inhalt = try json(anfrage)
        XCTAssertEqual(inhalt["barcode"] as? String, "4000000000013")
        XCTAssertEqual(inhalt["menge"] as? Double, 80)
        XCTAssertEqual(inhalt["einheit"] as? String, "g")
        XCTAssertEqual(inhalt["extern_id"] as? String, "app-1")
        XCTAssertEqual(inhalt["gehoert_zu"] as? String, "app-0")
        XCTAssertEqual(inhalt["geraet"] as? String, "iphone")
        XCTAssertEqual(inhalt["zeit"] as? String, "2026-03-15T07:30:00Z")
    }

    func testStandardmengeLaesstFelderWeg() throws {
        var scan = eintrag(.barcode)
        scan.barcode = "40000013"
        let inhalt = try json(scan.anfrage(bild: nil))
        XCTAssertNil(inhalt["menge"])
        XCTAssertNil(inhalt["einheit"])
        XCTAssertNil(inhalt["gehoert_zu"])
    }

    func testTextUndFavoritAnfrage() throws {
        var text = eintrag(.text)
        text.text = "Kaffee mit Milch"
        let textAnfrage = try text.anfrage(bild: nil)
        XCTAssertEqual(textAnfrage.pfad, "/api/essen/text")
        XCTAssertEqual(try json(textAnfrage)["text"] as? String, "Kaffee mit Milch")

        var favorit = eintrag(.favorit)
        favorit.favorit = "Müsli"
        favorit.faktor = 0.5
        let favoritAnfrage = try favorit.anfrage(bild: nil)
        XCTAssertEqual(favoritAnfrage.pfad, "/api/essen/favorit")
        XCTAssertEqual(try json(favoritAnfrage)["name"] as? String, "Müsli")
        XCTAssertEqual(try json(favoritAnfrage)["faktor"] as? Double, 0.5)
    }

    func testFotoAnfrageIstEinFormular() throws {
        var foto = eintrag(.foto)
        foto.notiz = "große Portion"
        foto.gramm = 350
        let bild = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])
        let anfrage = try foto.anfrage(bild: bild, grenze: "GRENZE")
        XCTAssertEqual(anfrage.pfad, "/api/essen/foto")
        XCTAssertEqual(anfrage.typ, "multipart/form-data; boundary=GRENZE")
        let anfang = "--GRENZE\r\nContent-Disposition: form-data; name=\"zeit\"\r\n\r\n2026-03-15T07:30:00Z\r\n"
        XCTAssertTrue(anfrage.koerper.starts(with: Data(anfang.utf8)))
        for teil in ["name=\"extern_id\"\r\n\r\napp-1\r\n", "name=\"geraet\"\r\n\r\niphone\r\n",
                     "name=\"notiz\"\r\n\r\ngroße Portion\r\n", "name=\"gramm\"\r\n\r\n350\r\n",
                     "name=\"foto\"; filename=\"foto.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"] {
            XCTAssertNotNil(anfrage.koerper.range(of: Data(teil.utf8)), teil)
        }
        XCTAssertNotNil(anfrage.koerper.range(of: bild + Data("\r\n--GRENZE--\r\n".utf8)))
        XCTAssertNil(anfrage.koerper.range(of: Data("gehoert_zu".utf8)))
    }

    func testFotoOhneBildWirdNichtGebaut() {
        XCTAssertThrowsError(try eintrag(.foto).anfrage(bild: nil))
    }

    // MARK: Antworten bewerten

    func testBewertung() {
        for status in [200, 201, 202] {
            XCTAssertEqual(Ergebnis.bewerten(status: status, art: .foto), .erledigt)
        }
        XCTAssertEqual(Ergebnis.bewerten(status: 401, art: .text), .neuKoppeln)
        for status in [413, 415, 422] {
            XCTAssertEqual(Ergebnis.bewerten(status: status, art: .foto), .fehlgeschlagen(nil))
        }
        XCTAssertEqual(Ergebnis.bewerten(status: 404, art: .favorit),
                       .fehlgeschlagen("Diesen Favoriten kennt der Server nicht."))
        for status in [0, 500, 502, 503] {
            XCTAssertEqual(Ergebnis.bewerten(status: status, art: .barcode), .spaeter)
        }
    }

    func testWartezeitWaechstBisEineStunde() {
        XCTAssertEqual(Ergebnis.wartezeit(versuche: 1), 30)
        XCTAssertEqual(Ergebnis.wartezeit(versuche: 2), 60)
        XCTAssertEqual(Ergebnis.wartezeit(versuche: 3), 120)
        XCTAssertEqual(Ergebnis.wartezeit(versuche: 50), 3600)
    }

    // MARK: Kleinigkeiten

    func testZahlen() {
        XCTAssertEqual(Zahl.text(80), "80")
        XCTAssertEqual(Zahl.text(0.5), "0.5")
        XCTAssertEqual(Zahl.lesen("0,5"), 0.5)
        XCTAssertEqual(Zahl.lesen(" 120 "), 120)
        XCTAssertNil(Zahl.lesen("viel"))
        XCTAssertNil(Zahl.lesen("0"))
        XCTAssertEqual(Zahl.kcal(304.4), "304 kcal")
    }

    func testEssenstagBisVierUhrFrueh() {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func zeit(_ tag: Int, _ stunde: Int) -> Date {
            kalender.date(from: DateComponents(year: 2026, month: 3, day: tag, hour: stunde, minute: 30))!
        }
        XCTAssertEqual(Essenstag.heute(jetzt: zeit(15, 12), kalender: kalender), "2026-03-15")
        XCTAssertEqual(Essenstag.heute(jetzt: zeit(16, 3), kalender: kalender), "2026-03-15")
        XCTAssertEqual(Essenstag.heute(jetzt: zeit(16, 4), kalender: kalender), "2026-03-16")
    }

    func testBarcodePruefung() {
        XCTAssertTrue(BarcodeBlatt.gueltig("4000000000013"))
        XCTAssertTrue(BarcodeBlatt.gueltig("40000013"))
        XCTAssertFalse(BarcodeBlatt.gueltig("abc"))
        XCTAssertFalse(BarcodeBlatt.gueltig("123"))
    }

    func testFotoWirdVerkleinert() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let gross = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: format).image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let daten = try XCTUnwrap(Bild.jpeg(gross))
        XCTAssertLessThanOrEqual(daten.count, Bild.hoechstens)
        XCTAssertEqual(Array(daten.prefix(2)), [0xFF, 0xD8])
        let klein = try XCTUnwrap(UIImage(data: daten))
        XCTAssertEqual(klein.size.width * klein.scale, 1600)
        XCTAssertEqual(klein.size.height * klein.scale, 1200)
    }

    // MARK: Warteschlange

    @MainActor
    private func leereSchlange() -> Warteschlange {
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("schlange-\(UUID().uuidString)")
        let schlange = Warteschlange(ordner: ordner)
        schlange.apiQuelle = { nil }
        return schlange
    }

    @MainActor
    func testWarteschlangeUeberlebtNeustart() throws {
        let schlange = leereSchlange()
        var foto = eintrag(.foto)
        foto.id = "app-foto"
        try schlange.aufnehmen(foto, bild: Data([1, 2, 3]))
        try schlange.aufnehmen(eintrag(.text))
        let neu = Warteschlange(ordner: schlange.ordner)
        XCTAssertEqual(neu.eintraege.map(\.id), ["app-foto", "app-1"])
        XCTAssertEqual(neu.eintraege.first?.zeit, foto.zeit)
        XCTAssertTrue(FileManager.default.fileExists(atPath: schlange.ordner.appendingPathComponent("app-foto.jpg").path))
        neu.loeschen("app-foto")
        XCTAssertFalse(FileManager.default.fileExists(atPath: schlange.ordner.appendingPathComponent("app-foto.jpg").path))
        XCTAssertEqual(Warteschlange(ordner: schlange.ordner).eintraege.map(\.id), ["app-1"])
    }

    @MainActor
    func testFotoOhneBildKommtNichtInDieSchlange() {
        let schlange = leereSchlange()
        XCTAssertThrowsError(try schlange.aufnehmen(eintrag(.foto)))
        XCTAssertTrue(schlange.eintraege.isEmpty)
    }

    @MainActor
    func testZurLetztenMahlzeit() throws {
        let schlange = leereSchlange()
        let start = Date(timeIntervalSince1970: 1_773_559_800)
        XCTAssertFalse(schlange.letzteMoeglich(jetzt: start))

        var erste = eintrag(.barcode)
        erste.id = "app-erste"
        try schlange.aufnehmen(erste, zurLetzten: true)  // es gibt noch keine: wird selbst die erste
        XCTAssertNil(schlange.eintraege[0].gehoertZu)
        XCTAssertTrue(schlange.letzteMoeglich(jetzt: start.addingTimeInterval(29 * 60)))
        XCTAssertFalse(schlange.letzteMoeglich(jetzt: start.addingTimeInterval(31 * 60)))

        var zweite = eintrag(.text)
        zweite.id = "app-zweite"
        zweite.zeit = start.addingTimeInterval(10 * 60)
        try schlange.aufnehmen(zweite, zurLetzten: true)
        XCTAssertEqual(schlange.eintraege[1].gehoertZu, "app-erste")

        // Auch das Dritte hängt an der ersten Mahlzeit, nicht an der zweiten.
        var dritte = eintrag(.favorit)
        dritte.id = "app-dritte"
        dritte.zeit = start.addingTimeInterval(20 * 60)
        try schlange.aufnehmen(dritte, zurLetzten: true)
        XCTAssertEqual(schlange.eintraege[2].gehoertZu, "app-erste")

        // Nach 30 Minuten beginnt eine neue Mahlzeit, auch wenn der Schalter an ist.
        var spaet = eintrag(.favorit)
        spaet.id = "app-spaet"
        spaet.zeit = start.addingTimeInterval(45 * 60)
        try schlange.aufnehmen(spaet, zurLetzten: true)
        XCTAssertNil(schlange.eintraege[3].gehoertZu)
    }

    @MainActor
    func testOhneServerBleibtAllesLiegen() async throws {
        let schlange = leereSchlange()
        try schlange.aufnehmen(eintrag(.text))
        await schlange.senden(alle: true)
        XCTAssertEqual(schlange.eintraege.count, 1)
        XCTAssertEqual(schlange.eintraege[0].stand, .wartet)
    }
}
