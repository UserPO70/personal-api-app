import XCTest
@testable import PersonalAPI

/// Mehrere Fotos je Mahlzeit: Senden, Warteschlange und die Fotoliste vom Server.
final class FotosTests: XCTestCase {
    private func foto(_ id: String = "app-teller") -> Eintrag {
        Eintrag(id: id, art: .foto, zeit: Date(timeIntervalSince1970: 1_773_559_800), titel: "2 Fotos")
    }

    @MainActor
    private func leereSchlange() -> Warteschlange {
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-\(UUID().uuidString)")
        let schlange = Warteschlange(ordner: ordner)
        schlange.apiQuelle = { nil }
        return schlange
    }

    private func anzahl(_ teil: String, in daten: Data) -> Int {
        var zaehler = 0
        var rest = daten.startIndex..<daten.endIndex
        while let fund = daten.range(of: Data(teil.utf8), in: rest) {
            zaehler += 1
            rest = fund.upperBound..<daten.endIndex
        }
        return zaehler
    }

    func testMehrereFotosInEinerAnfrage() throws {
        let teller = Data([0xFF, 0xD8, 0x01])
        let packung = Data([0xFF, 0xD8, 0x02])
        let anfrage = try foto().anfrage(bilder: [teller, packung], grenze: "GRENZE")
        XCTAssertEqual(anfrage.pfad, "/api/essen/foto")
        // Das Feld `foto` steht zweimal da, so liest der Server mehrere Fotos einer Mahlzeit.
        XCTAssertEqual(anzahl("name=\"foto\"", in: anfrage.koerper), 2)
        XCTAssertNotNil(anfrage.koerper.range(of: Data("filename=\"foto.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8) + teller + Data("\r\n--GRENZE\r\n".utf8)))
        XCTAssertNotNil(anfrage.koerper.range(of: Data("filename=\"foto-2.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8) + packung + Data("\r\n--GRENZE--\r\n".utf8)))
        XCTAssertEqual(anzahl("--GRENZE--", in: anfrage.koerper), 1)
    }

    func testLeeresBildWirdNichtGesendet() {
        XCTAssertThrowsError(try foto().anfrage(bilder: [Data([1]), Data()]))
        XCTAssertThrowsError(try foto().anfrage(bilder: []))
    }

    @MainActor
    func testWarteschlangeMerktSichAlleFotos() throws {
        let schlange = leereSchlange()
        try schlange.aufnehmen(foto(), bilder: [Data([1]), Data([2]), Data([3])])
        let datei = { (nummer: Int) in schlange.bildDatei("app-teller", nummer: nummer).path }
        XCTAssertEqual(schlange.eintraege.first?.fotos, 3)
        XCTAssertEqual(schlange.eintraege.first?.fotoAnzahl, 3)
        for nummer in 1...3 {
            XCTAssertTrue(FileManager.default.fileExists(atPath: datei(nummer)), "Bild \(nummer)")
        }
        XCTAssertTrue(datei(1).hasSuffix("app-teller.jpg"))
        XCTAssertTrue(datei(2).hasSuffix("app-teller-2.jpg"))

        // Nach einem Neustart weiß die Schlange noch, dass drei Fotos dazugehören.
        let neu = Warteschlange(ordner: schlange.ordner)
        XCTAssertEqual(neu.eintraege.first?.fotoAnzahl, 3)
        neu.loeschen("app-teller")
        for nummer in 1...3 {
            XCTAssertFalse(FileManager.default.fileExists(atPath: datei(nummer)), "Bild \(nummer)")
        }
    }

    @MainActor
    func testHoechstensVierFotos() {
        let schlange = leereSchlange()
        XCTAssertThrowsError(try schlange.aufnehmen(foto(), bilder: Array(repeating: Data([1]), count: 5)))
        XCTAssertTrue(schlange.eintraege.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: schlange.bildDatei("app-teller").path))
    }

    /// Einträge aus älteren Versionen haben kein Feld `fotos`: Sie gelten als ein Foto.
    func testAlterEintragHatEinFoto() throws {
        var alt = foto()
        alt.fotos = nil
        XCTAssertEqual(alt.fotoAnzahl, 1)
        var text = foto()
        text.art = .text
        XCTAssertEqual(text.fotoAnzahl, 0)
    }

    @MainActor
    func testEbenErfasstMitTitelUndFotoErgaenzen() throws {
        let schlange = leereSchlange()
        try schlange.aufnehmen(foto(), bilder: [Data([1])])
        XCTAssertEqual(schlange.letzte?.id, "app-teller")
        XCTAssertEqual(schlange.letzte?.titel, "2 Fotos")

        // „Foto ergänzen“ zehn Minuten später hängt an der eben erfassten Mahlzeit.
        var nachtisch = foto("app-nachtisch")
        nachtisch.zeit = nachtisch.zeit.addingTimeInterval(10 * 60)
        try schlange.aufnehmen(nachtisch, bilder: [Data([2])], zurLetzten: true)
        XCTAssertEqual(schlange.eintraege[1].gehoertZu, "app-teller")
        XCTAssertEqual(schlange.letzte?.id, "app-teller")
    }

    func testFotolisteVomServer() throws {
        let json = """
        {"id": 7, "quelle": "foto", "foto_auftrag_ids": [3],
         "fotos": [{"auftrag_id": 3, "nr": 1, "adresse": "/api/essen/foto/3/bild?nr=1"},
                   {"auftrag_id": 3, "nr": 2, "adresse": "/api/essen/foto/3/bild?nr=2"}]}
        """
        let mahlzeit = try JSONDecoder().decode(Mahlzeit.self, from: Data(json.utf8))
        XCTAssertEqual(mahlzeit.fotos, [3])
        XCTAssertEqual(mahlzeit.bildpfade, ["/api/essen/foto/3/bild?nr=1", "/api/essen/foto/3/bild?nr=2"])
    }

    /// Ältere Server kennen die Liste noch nicht: Dann das erste Foto je Auftrag.
    func testFotolisteOhneListe() throws {
        let json = #"{"id": 7, "quelle": "foto", "foto_auftrag_ids": [3, 4]}"#
        let mahlzeit = try JSONDecoder().decode(Mahlzeit.self, from: Data(json.utf8))
        XCTAssertEqual(mahlzeit.bildpfade, ["/api/essen/foto/3/bild", "/api/essen/foto/4/bild"])
    }
}
