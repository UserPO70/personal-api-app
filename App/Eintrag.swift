import Foundation

/// Eine Erfassung in der Warteschlange. `id` ist die `extern_id`: Der Server erkennt daran Doppelte,
/// deshalb darf ein Eintrag beliebig oft gesendet werden.
struct Eintrag: Codable, Equatable, Identifiable {
    enum Art: String, Codable {
        case foto, barcode, text, favorit, gewicht
    }

    enum Stand: String, Codable {
        case wartet, fehlgeschlagen
    }

    var id: String
    var art: Art
    var zeit: Date
    var titel: String
    var notiz: String?
    var gramm: Double?
    var gehoertZu: String?
    var barcode: String?
    var menge: Double?
    var einheit: String?
    var text: String?
    var favorit: String?
    var faktor: Double?
    /// Körpergewicht in kg (Art `gewicht`).
    var kg: Double?
    /// Barcode: Claude schätzt die Menge aus der Notiz, die Nährwerte bleiben die der Packung.
    var mengeSchaetzen: Bool?
    var versuche: Int = 0
    var naechsterVersuch: Date?
    var stand: Stand = .wartet
    var hinweis: String?

    static func neueKennung() -> String {
        "app-" + UUID().uuidString.lowercased()
    }

    /// Fotos und Texte schätzt Claude, das braucht die Zustimmung.
    var brauchtZustimmung: Bool { art == .foto || art == .text || mengeSchaetzen == true }

    var symbol: String {
        switch art {
        case .foto: return "camera"
        case .barcode: return "barcode"
        case .text: return "text.cursor"
        case .favorit: return "star"
        case .gewicht: return "scalemass"
        }
    }
}

/// Was an den Server geht.
struct Anfrage: Equatable {
    let pfad: String
    let typ: String
    let koerper: Data
}

enum EintragFehler: Error {
    case fotoFehlt
}

extension Eintrag {
    /// Gleiche Kennung des Geräts wie die Kurzbefehle, sonst legt der Server „zur letzten Mahlzeit“ nicht zusammen.
    static let geraet = "iphone"

    var zeitText: String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: zeit)
    }

    func anfrage(bild: Data?, grenze: String = "Grenze-" + UUID().uuidString) throws -> Anfrage {
        switch art {
        case .foto:
            guard let bild, !bild.isEmpty else { throw EintragFehler.fotoFehlt }
            var felder: [(String, String)] = [("zeit", zeitText), ("geraet", Self.geraet), ("extern_id", id)]
            if let notiz, !notiz.isEmpty { felder.append(("notiz", notiz)) }
            if let gramm { felder.append(("gramm", Zahl.text(gramm))) }
            if let gehoertZu { felder.append(("gehoert_zu", gehoertZu)) }
            return Anfrage(pfad: "/api/essen/foto", typ: "multipart/form-data; boundary=\(grenze)",
                           koerper: Formular.bauen(felder: felder, datei: bild, grenze: grenze))
        case .barcode:
            var json = grundfelder()
            json["barcode"] = barcode ?? ""
            if let menge { json["menge"] = menge }
            if let einheit { json["einheit"] = einheit }
            if mengeSchaetzen == true { json["menge_schaetzen"] = true }
            return try Self.json("/api/essen/barcode", json)
        case .text:
            var json = grundfelder()
            json["text"] = text ?? ""
            return try Self.json("/api/essen/text", json)
        case .favorit:
            var json = grundfelder()
            json["name"] = favorit ?? ""
            if let faktor { json["faktor"] = faktor }
            return try Self.json("/api/essen/favorit", json)
        case .gewicht:
            var json: [String: Any] = ["kg": kg ?? 0, "zeit": zeitText, "quelle": "app", "extern_id": id]
            if let notiz, !notiz.isEmpty { json["notiz"] = notiz }
            return try Self.json("/api/koerper/gewicht", json)
        }
    }

    private func grundfelder() -> [String: Any] {
        var json: [String: Any] = ["zeit": zeitText, "geraet": Self.geraet, "extern_id": id]
        if let gehoertZu { json["gehoert_zu"] = gehoertZu }
        if let notiz, !notiz.isEmpty, art != .text { json["notiz"] = notiz }
        return json
    }

    private static func json(_ pfad: String, _ inhalt: [String: Any]) throws -> Anfrage {
        Anfrage(pfad: pfad, typ: "application/json",
                koerper: try JSONSerialization.data(withJSONObject: inhalt, options: [.sortedKeys]))
    }
}

enum Formular {
    /// Formular mit Textfeldern und dem Foto im Feld `foto`.
    static func bauen(felder: [(String, String)], datei: Data, grenze: String) -> Data {
        var daten = Data()
        for (name, wert) in felder {
            daten.append(Data("--\(grenze)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(wert)\r\n".utf8))
        }
        daten.append(Data("--\(grenze)\r\nContent-Disposition: form-data; name=\"foto\"; filename=\"foto.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        daten.append(datei)
        daten.append(Data("\r\n--\(grenze)--\r\n".utf8))
        return daten
    }
}

/// Was die App mit einer Antwort des Servers macht.
enum Ergebnis: Equatable {
    /// Angekommen (auch als Doppeltes): Eintrag löschen.
    case erledigt
    /// Der Schlüssel gilt nicht mehr: Senden anhalten, alles behalten.
    case neuKoppeln
    /// Kommt nie von selbst durch: sichtbar behalten, mit Erneut und Löschen.
    case fehlgeschlagen(String?)
    /// Server nicht bereit oder nicht erreichbar: später erneut.
    case spaeter

    static func bewerten(status: Int, art: Eintrag.Art) -> Ergebnis {
        switch status {
        case 200..<300:
            return .erledigt
        case 401, 403:
            return .neuKoppeln
        case 404 where art == .favorit:
            return .fehlgeschlagen("Diesen Favoriten kennt der Server nicht.")
        case 408, 425, 429:
            return .spaeter
        case 400..<500:
            return .fehlgeschlagen(nil)
        default:
            return .spaeter
        }
    }

    /// Abstand bis zum nächsten Versuch: 30 s, 1 min, 2 min, … höchstens 1 Stunde.
    static func wartezeit(versuche: Int) -> TimeInterval {
        let stufe = min(max(versuche - 1, 0), 10)
        return min(30 * pow(2, Double(stufe)), 3600)
    }
}
