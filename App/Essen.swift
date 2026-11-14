import Foundation

/// Antworten des Servers rund ums Essen. Nur die Teile, die die App zeigt; alles Übrige wird überlesen.
struct Naehrwerte: Codable, Equatable {
    var kcal: Double?
    var eiweiss: Double?
    var kohlenhydrate: Double?
    var fett: Double?

    enum CodingKeys: String, CodingKey {
        case kcal
        case eiweiss = "eiweiss_g"
        case kohlenhydrate = "kohlenhydrate_g"
        case fett = "fett_g"
    }
}

struct Bestandteil: Codable, Equatable {
    var lebensmittel: String?
    var menge: Double?
    var einheit: String?
    var kcal: Double?
    var eiweiss: Double?
    var kohlenhydrate: Double?
    var fett: Double?

    enum CodingKeys: String, CodingKey {
        case lebensmittel, menge, einheit, kcal
        case eiweiss = "eiweiss_g"
        case kohlenhydrate = "kohlenhydrate_g"
        case fett = "fett_g"
    }

    /// „250 g“, „2 Stück“ oder leer.
    var mengeText: String {
        guard let menge else { return "" }
        let zahl = Zahl.text(menge).replacingOccurrences(of: ".", with: ",")
        return einheit.map { "\(zahl) \($0)" } ?? zahl
    }
}

struct Mahlzeit: Codable, Equatable, Identifiable {
    /// Was der Server zur Herkunft der Zahlen weiß. Je nach Quelle fehlt das meiste, deshalb wird nachsichtig gelesen.
    struct Einschaetzung: Codable, Equatable {
        var sicherheit: String?
        var hinweis: String?
        var gewogen: Double?

        enum CodingKeys: String, CodingKey {
            case sicherheit, hinweis
            case gewogen = "gewogen_g"
        }

        init(sicherheit: String? = nil, hinweis: String? = nil, gewogen: Double? = nil) {
            self.sicherheit = sicherheit
            self.hinweis = hinweis
            self.gewogen = gewogen
        }

        init(from decoder: Decoder) throws {
            let werte = try decoder.container(keyedBy: CodingKeys.self)
            sicherheit = try? werte.decodeIfPresent(String.self, forKey: .sicherheit)
            hinweis = try? werte.decodeIfPresent(String.self, forKey: .hinweis)
            gewogen = try? werte.decodeIfPresent(Double.self, forKey: .gewogen)
        }
    }

    var id: Int
    var uhrzeit: String?
    var quelle: String?
    var notiz: String?
    var art: String?
    var bestandteile: [Bestandteil]?
    var summe: Naehrwerte?
    var daten: Einschaetzung?
    var fotos: [Int]?
    var artGeschaetzt: Bool?
    var korrigiert: Bool?
    var aenderbar: Bool?

    enum CodingKeys: String, CodingKey {
        case id, uhrzeit, quelle, notiz, art, bestandteile, summe, daten, korrigiert, aenderbar
        case fotos = "foto_auftrag_ids"
        case artGeschaetzt = "art_geschaetzt"
    }

    static let arten = ["Frühstück", "Mittag", "Abend", "Snack"]

    /// Woher die Zahlen stammen, in Worten.
    var herkunft: String {
        if korrigiert == true { return "von Hand korrigiert" }
        switch quelle {
        case "foto": return daten?.gewogen != nil ? "Foto, Menge gewogen" : "Foto, von Claude geschätzt"
        case "text": return "Text, von Claude geschätzt"
        case "barcode": return "Barcode, Nährwerte von der Packung"
        case "health": return "aus Apple Health"
        case "manuell": return "von Hand eingetragen oder Favorit"
        default: return quelle ?? "unbekannt"
        }
    }

    /// Stammen die Zahlen aus einer Schätzung?
    var geschaetzt: Bool {
        korrigiert != true && (quelle == "text" || (quelle == "foto" && daten?.gewogen == nil))
    }

    var titel: String {
        let namen = (bestandteile ?? []).compactMap(\.lebensmittel)
        if namen.isEmpty { return notiz ?? "Mahlzeit" }
        return namen.joined(separator: ", ")
    }
}

/// GET /api/essen/tag
struct Essenstag: Codable, Equatable {
    var tag: String
    var anzahl: Int
    var summe: Naehrwerte?
    var mahlzeiten: [Mahlzeit]

    /// Der laufende Essenstag: Bis 4 Uhr früh zählt noch der Tag davor (wie am Server).
    static func heute(jetzt: Date = Date(), kalender: Calendar = .current) -> String {
        let teile = kalender.dateComponents([.year, .month, .day], from: jetzt.addingTimeInterval(-4 * 3600))
        return String(format: "%04d-%02d-%02d", teile.year ?? 0, teile.month ?? 0, teile.day ?? 0)
    }
}

/// Antwort auf das Senden: bei Foto und Text die Nummer des Auftrags, sonst die der Mahlzeit.
struct Sendeantwort: Codable, Equatable {
    var id: Int?
    var doppelt: Bool?
    var status: String?
    var hinweis: String?
}

/// GET /api/essen/foto/{id}
struct Auftragsstand: Codable, Equatable {
    var id: Int
    var status: String
    var fehler: String?
}

/// GET /api/essen/barcode/{code}
struct BarcodeAuskunft: Codable, Equatable {
    struct Produkt: Codable, Equatable {
        var name: String?
        var bezeichnung: String?
        var packungsgroesse: String?
        var portion: Double?
        var stueck: Double?
        var je100: Naehrwerte?

        enum CodingKeys: String, CodingKey {
            case name, bezeichnung, packungsgroesse
            case portion = "portion_g"
            case stueck = "stueck_g"
            case je100 = "je_100"
        }
    }
    /// Was der Server mit einer Einheit für dieses Produkt anfangen kann.
    struct Einheit: Codable, Equatable {
        var einheit: String
        var rechnet: Bool
        var gramm: Double?
        var hinweis: String?
        var wiePortion: Bool?

        enum CodingKeys: String, CodingKey {
            case einheit, rechnet, gramm, hinweis
            case wiePortion = "wie_portion"
        }
    }

    /// Was gilt, wenn keine Menge angegeben wird.
    struct Standard: Codable, Equatable {
        var menge: Double?
        var einheit: String?
        var gramm: Double?
        var rechnet: Bool?
    }

    var barcode: String
    var gefunden: Bool
    var produkt: Produkt?
    var einheiten: [Einheit]?
    var standard: Standard?
}

extension BarcodeAuskunft {
    static let alleEinheiten = ["g", "ml", "Portion", "Stück"]

    /// Einheiten, mit denen der Server Nährwerte berechnen kann. Sagt er nichts dazu, alle.
    var waehlbar: [String] {
        guard let einheiten else { return Self.alleEinheiten }
        return einheiten.filter(\.rechnet).map(\.einheit)
    }

    /// Einheiten, die für dieses Produkt nicht gehen, mit dem Grund des Servers.
    var nichtWaehlbar: [Einheit] {
        (einheiten ?? []).filter { !$0.rechnet }
    }

    func angabe(_ einheit: String) -> Einheit? {
        einheiten?.first { $0.einheit == einheit }
    }

    /// Kalorien für die gewählte Menge; `einheit` nil heißt Standard. Gerechnet mit den Angaben des Servers.
    func kcal(menge: Double?, einheit: String?) -> Double? {
        guard let je100 = produkt?.je100?.kcal else { return nil }
        guard let einheit else {
            guard standard?.rechnet != false, let gramm = standard?.gramm else { return nil }
            return je100 * gramm / 100
        }
        guard let menge, let angabe = angabe(einheit), angabe.rechnet, let gramm = angabe.gramm else { return nil }
        return je100 * menge * gramm / 100
    }

    /// „1 Portion (50 g)“ oder „100 g“.
    var standardText: String? {
        guard let standard, let einheit = standard.einheit else { return nil }
        let menge = Zahl.text(standard.menge ?? 1)
        if einheit == "g" || einheit == "ml" { return "\(menge) \(einheit)" }
        guard let gramm = standard.gramm else { return "\(menge) \(einheit)" }
        return "\(menge) \(einheit) (\(Zahl.text(gramm)) g)"
    }
}

/// GET /api/essen/favoriten
struct Favoritenliste: Codable, Equatable {
    struct Favorit: Codable, Equatable, Identifiable {
        var id: Int
        var name: String
        var summe: Naehrwerte?
    }
    var favoriten: [Favorit]
}

enum Zahl {
    /// 80 statt 80.0, 0.5 bleibt 0.5; immer mit Punkt, wie der Server es liest.
    static func text(_ wert: Double) -> String {
        wert == wert.rounded() && abs(wert) < 1e9 ? String(Int(wert)) : String(wert)
    }

    /// Liest auch „0,5“.
    static func lesen(_ text: String) -> Double? {
        let sauber = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let wert = Double(sauber), wert > 0, wert.isFinite else { return nil }
        return wert
    }

    static func kcal(_ wert: Double?) -> String {
        guard let wert else { return "– kcal" }
        return "\(Int(wert.rounded())) kcal"
    }

    static func gramm(_ wert: Double?) -> String {
        guard let wert else { return "–" }
        return "\(Int(wert.rounded())) g"
    }
}
