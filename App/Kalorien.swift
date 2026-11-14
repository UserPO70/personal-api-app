import Foundation
import SwiftUI

/// GET und PUT /api/kalorien/profil: Angaben zur Person, Rechnung und das heute geltende Ziel.
struct Kalorienstand: Codable, Equatable {
    struct Angaben: Codable, Equatable {
        var groesse: Double
        var geburtsjahr: Int
        var geschlecht: String
        var aktivitaet: String
        var ziel: String
        var kgProWoche: Double?
        var eigenesZiel: Double?

        enum CodingKeys: String, CodingKey {
            case geburtsjahr, geschlecht, aktivitaet, ziel
            case groesse = "groesse_cm"
            case kgProWoche = "kg_pro_woche"
            case eigenesZiel = "eigenes_ziel_kcal"
        }
    }

    struct Rechnung: Codable, Equatable {
        var gewicht: Double?
        var grundumsatz: Double?
        var bedarf: Double?
        var ziel: Double?
        var zielGerechnet: Double?
        var quelle: String?
        var rechenweg: [String]
        var grenzen: [String]
        var grund: String?

        enum CodingKeys: String, CodingKey {
            case quelle, rechenweg, grenzen, grund
            case gewicht = "gewicht_kg"
            case grundumsatz = "grundumsatz_kcal"
            case bedarf = "bedarf_kcal"
            case ziel = "ziel_kcal"
            case zielGerechnet = "ziel_gerechnet_kcal"
        }
    }

    struct Ziel: Codable, Equatable {
        var kcal: Double
        var quelle: String?
        var giltAb: String?

        enum CodingKeys: String, CodingKey {
            case kcal, quelle
            case giltAb = "gilt_ab"
        }
    }

    struct Stufe: Codable, Equatable, Identifiable {
        var stufe: String
        var name: String
        var beschreibung: String

        var id: String { stufe }
    }

    var angaben: Angaben?
    var rechnung: Rechnung?
    var ziel: Ziel?
    var abweichung: Double?
    var stufen: [Stufe]
    var grund: String?
    var hinweis: String?

    enum CodingKeys: String, CodingKey {
        case angaben, rechnung, ziel, stufen, grund, hinweis
        case abweichung = "abweichung_kcal"
    }
}

/// GET /api/kalorien/verlauf
struct Kalorienverlauf: Codable, Equatable {
    struct Tag: Codable, Equatable, Identifiable {
        var tag: String
        var kcal: Double?
        var ziel: Double?

        var id: String { tag }

        enum CodingKeys: String, CodingKey {
            case tag, kcal
            case ziel = "ziel_kcal"
        }
    }

    struct Wochenmittel: Codable, Equatable {
        var tageMitEssen: Int?
        var kcal: Double?
        var ziel: Double?

        enum CodingKeys: String, CodingKey {
            case kcal
            case tageMitEssen = "tage_mit_essen"
            case ziel = "ziel_kcal"
        }
    }

    struct Gegenprobe: Codable, Equatable {
        var tageMitEssen: Int?
        var mittelGegessen: Double?
        var kgProWoche: Double?
        var bedarfGeschaetzt: Double?
        var bedarfGerechnet: Double?
        var abweichungProzent: Int?
        var hinweis: String?
        var grund: String?

        enum CodingKeys: String, CodingKey {
            case hinweis, grund
            case tageMitEssen = "tage_mit_essen"
            case mittelGegessen = "mittel_gegessen_kcal"
            case kgProWoche = "kg_pro_woche"
            case bedarfGeschaetzt = "bedarf_geschaetzt_kcal"
            case bedarfGerechnet = "bedarf_gerechnet_kcal"
            case abweichungProzent = "abweichung_prozent"
        }
    }

    var tage: [Tag]
    var wochenmittel: Wochenmittel?
    var gegenprobe: Gegenprobe?

    /// Obergrenze der Kalorienachse: etwas Luft über dem größten Wert, auf volle 500.
    var achse: ClosedRange<Double> {
        let hoechster = (tage.compactMap(\.kcal) + tage.compactMap(\.ziel)).max() ?? 2000
        return 0...((hoechster * 1.1 / 500).rounded(.up) * 500)
    }
}

/// Was im Formular steht. Zahlen bleiben Text, der Server liest auch „178,5“ und „0,5“.
struct Kalorieneingabe: Equatable {
    static let tempi: [Double] = [0.25, 0.5, 0.75, 1]

    var groesse = ""
    var geburtsjahr = ""
    var geschlecht = "m"
    var aktivitaet = "leicht"
    var ziel = "halten"
    var tempo = 0.5
    var eigenesZiel = ""

    init() {}

    init(_ angaben: Kalorienstand.Angaben) {
        groesse = Zahl.text(angaben.groesse).replacingOccurrences(of: ".", with: ",")
        geburtsjahr = String(angaben.geburtsjahr)
        geschlecht = angaben.geschlecht
        aktivitaet = angaben.aktivitaet
        ziel = angaben.ziel
        tempo = angaben.kgProWoche ?? 0.5
        eigenesZiel = angaben.eigenesZiel.map { Zahl.text($0) } ?? ""
    }

    /// Grobe Prüfung vor dem Senden, mit denselben Grenzen wie am Server. `nil` heißt: in Ordnung.
    func fehler(jahr: Int = Calendar.current.component(.year, from: Date())) -> String? {
        guard let cm = Zahl.lesen(groesse), cm >= 100, cm <= 250 else {
            return "Bitte die Größe in cm eingeben, zwischen 100 und 250."
        }
        guard let geboren = Int(geburtsjahr.trimmingCharacters(in: .whitespaces)),
              jahr - geboren >= 14, jahr - geboren <= 120 else {
            return "Bitte das Geburtsjahr eingeben, z. B. 1990."
        }
        let eigenes = eigenesZiel.trimmingCharacters(in: .whitespaces)
        if !eigenes.isEmpty {
            guard let kcal = Zahl.lesen(eigenes), kcal >= 800, kcal <= 8000 else {
                return "Das eigene Ziel muss zwischen 800 und 8000 kcal liegen."
            }
        }
        return nil
    }

    /// Inhalt für PUT /api/kalorien/profil.
    var json: [String: String] {
        var inhalt = ["groesse_cm": groesse.trimmingCharacters(in: .whitespaces),
                      "geburtsjahr": geburtsjahr.trimmingCharacters(in: .whitespaces),
                      "geschlecht": geschlecht, "aktivitaet": aktivitaet, "ziel": ziel]
        if ziel != "halten" { inhalt["kg_pro_woche"] = Zahl.text(tempo) }
        let eigenes = eigenesZiel.trimmingCharacters(in: .whitespaces)
        if !eigenes.isEmpty { inhalt["eigenes_ziel_kcal"] = eigenes }
        return inhalt
    }
}

enum Kalorientext {
    /// „noch 688 kcal offen“ bzw. „111 kcal über dem Ziel“. Ohne Wertung.
    static func offen(gegessen: Double?, ziel: Double) -> String {
        let rest = ziel - (gegessen ?? 0)
        if rest >= 0.5 { return "noch \(Int(rest.rounded())) kcal offen" }
        if rest <= -0.5 { return "\(Int((-rest).rounded())) kcal über dem Ziel" }
        return "Ziel erreicht"
    }

    /// Anteil für den Balken, zwischen 0 und 1.
    static func anteil(gegessen: Double?, ziel: Double) -> Double {
        guard ziel > 0 else { return 0 }
        return min(max((gegessen ?? 0) / ziel, 0), 1)
    }

    static func tempo(_ kg: Double) -> String {
        "\(Zahl.text(kg).replacingOccurrences(of: ".", with: ",")) kg je Woche"
    }

    static func ziel(_ ziel: String) -> String {
        switch ziel {
        case "abnehmen": return "Abnehmen"
        case "zunehmen": return "Zunehmen"
        default: return "Halten"
        }
    }
}

extension Color {
    /// Bereichsfarbe „essen“ aus dem Designkonzept, hell und dunkel.
    static let essen = Color(uiColor: UIColor { merkmale in
        merkmale.userInterfaceStyle == .dark
            ? UIColor(red: 0xC0 / 255, green: 0x5F / 255, blue: 0x0D / 255, alpha: 1)
            : UIColor(red: 0xE0 / 255, green: 0x5A / 255, blue: 0x03 / 255, alpha: 1)
    })
}
