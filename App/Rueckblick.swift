import Foundation

/// GET /api/rueckblick?art=woche|monat&tag=JJJJ-MM-TT: eine Kalenderwoche oder ein Kalendermonat im Vergleich
/// zur Vorperiode. Der Server rechnet alles; die App liest nur, was sie zeigt (der Rest der Antwort wird übergangen).
struct Rueckblick: Codable, Equatable {
    /// Tagesdurchschnitt über die Tage mit Daten (`tage`); `summe` fehlt bei Werten, die schon Mittel sind.
    struct Wert: Codable, Equatable {
        var summe: Double?
        var schnitt: Double?
        var tage: Int
    }

    struct Vergleich: Codable, Equatable {
        var differenz: Double
        var prozent: Double?
    }

    struct Kennzahl: Codable, Equatable, Identifiable {
        var schluessel: String
        var name: String
        var einheit: String
        var bereich: String
        var jetzt: Wert
        var vorher: Wert
        var vergleich: Vergleich?

        var id: String { schluessel }
    }

    struct Gewicht: Codable, Equatable {
        struct Veraenderung: Codable, Equatable {
            var kg: Double
        }

        var messungen: Int
        var messungenVorher: Int
        var veraenderung: Veraenderung?

        enum CodingKeys: String, CodingKey {
            case messungen, veraenderung
            case messungenVorher = "messungen_vorher"
        }
    }

    struct Abschnitt: Codable, Equatable {
        struct Ort: Codable, Equatable, Identifiable {
            var name: String
            var minuten: Double
            var id: String { name }
        }

        struct Strecke: Codable, Equatable, Identifiable {
            var strecke: String
            var anzahl: Int
            var id: String { strecke }
        }

        struct Fahrten: Codable, Equatable {
            var anzahl: Int
            var minuten: Double
            var streckeKm: Double
            var haeufigste: [Strecke]

            enum CodingKeys: String, CodingKey {
                case anzahl, minuten, haeufigste
                case streckeKm = "strecke_km"
            }
        }

        var von: String
        var bis: String
        var orte: [Ort]
        var orteAnzahl: Int
        var neueOrte: [String]
        var fahrten: Fahrten

        enum CodingKeys: String, CodingKey {
            case von, bis, orte, fahrten
            case orteAnzahl = "orte_anzahl"
            case neueOrte = "neue_orte"
        }
    }

    struct Pc: Codable, Equatable {
        struct Zeile: Codable, Equatable, Identifiable {
            var name: String
            var jetzt: Wert
            var vorher: Wert
            var vergleich: Vergleich?
            var id: String { name }
        }

        var fehler: String?
        var tage: Int
        var kategorien: [Zeile]
    }

    struct Essen: Codable, Equatable {
        struct Fenster: Codable, Equatable {
            struct Teil: Codable, Equatable {
                var tage: Int
                var erste: String?
                var letzte: String?
            }

            var jetzt: Teil
            var vorher: Teil
        }

        /// Kalorienziel: nur vollständige Essenstage mit Ziel. Fehlt ohne Angaben zum Kalorienrechner.
        struct Ziel: Codable, Equatable {
            struct Teil: Codable, Equatable {
                var tageMitZiel: Int
                var zielSchnittKcal: Double?
                var tageVollstaendig: Int
                var tageUnvollstaendig: Int?
                var tageEssenOhneZiel: Int?
                var abweichungSchnittKcal: Double?
                var abweichungSchnittProzent: Double?
                var tageImZielbereich: Int?
                var anteilImZielbereichProzent: Double?

                enum CodingKeys: String, CodingKey {
                    case tageMitZiel = "tage_mit_ziel"
                    case zielSchnittKcal = "ziel_schnitt_kcal"
                    case tageVollstaendig = "tage_vollstaendig"
                    case tageUnvollstaendig = "tage_unvollstaendig"
                    case tageEssenOhneZiel = "tage_essen_ohne_ziel"
                    case abweichungSchnittKcal = "abweichung_schnitt_kcal"
                    case abweichungSchnittProzent = "abweichung_schnitt_prozent"
                    case tageImZielbereich = "tage_im_zielbereich"
                    case anteilImZielbereichProzent = "anteil_im_zielbereich_prozent"
                }
            }

            var zielbereichProzent: Double
            var jetzt: Teil
            var vorher: Teil

            enum CodingKeys: String, CodingKey {
                case jetzt, vorher
                case zielbereichProzent = "zielbereich_prozent"
            }
        }

        var fenster: Fenster
        var ziel: Ziel?
    }

    var art: String
    var von: String
    var bis: String
    var tageGesamt: Int
    var tageAusgewertet: Int
    var laeuftNoch: Bool
    var kennzahlen: [Kennzahl]
    var gewicht: Gewicht
    var jetzt: Abschnitt
    var vorher: Abschnitt
    var pc: Pc
    var essen: Essen
    var zurueck: String
    var weiter: String

    enum CodingKeys: String, CodingKey {
        case art, von, bis, kennzahlen, gewicht, jetzt, vorher, pc, essen, zurueck, weiter
        case tageGesamt = "tage_gesamt"
        case tageAusgewertet = "tage_ausgewertet"
        case laeuftNoch = "laeuft_noch"
    }

    // MARK: Auswahl für die Anzeige

    static let gesundheit = ["schritte", "strecke_km", "gehtempo_kmh", "schrittlaenge_cm", "schlaf_minuten", "gewicht_kg"]
    static let ernaehrung = ["kcal", "eiweiss_g", "kohlenhydrate_g", "fett_g"]
    static let unterwegs = ["unterwegs_minuten", "fahrten"]

    /// Die Kennzahlen mit diesen Schlüsseln, die im Zeitraum Daten haben, in dieser Reihenfolge.
    func mitDaten(_ schluessel: [String]) -> [Kennzahl] {
        schluessel.compactMap { kennzahl($0) }
    }

    func kennzahl(_ schluessel: String) -> Kennzahl? {
        kennzahlen.first { $0.schluessel == schluessel && $0.jetzt.tage > 0 }
    }

    var leer: Bool { kennzahlen.allSatisfy { $0.jetzt.tage == 0 } && jetzt.orteAnzahl == 0 }

    /// „Vorwoche“ oder „Vormonat“.
    var vorperiode: String { art == "monat" ? "Vormonat" : "Vorwoche" }

    /// „KW 11 · 9.–15. März 2026“ bzw. „März 2026“.
    var titel: String { Rueckblicktext.zeitraum(art: art, von: von, bis: bis) }

    /// Weiter geht es nur bis zum laufenden Zeitraum, nicht in die Zukunft.
    func weiterMoeglich(heute: String) -> Bool { weiter <= heute }
}

/// Texte des Rückblicks: Werte je Einheit, Vergleich mit der Vorperiode, Zeitraum.
enum Rueckblicktext {
    private static let deutsch = Locale(identifier: "de_DE")

    /// Ein Wert in der Einheit seiner Kennzahl: „6.794“, „5,4 km“, „7 h 1 min“, „82,7 kg“, „6,1 GB“.
    static func wert(_ wert: Double, schluessel: String) -> String {
        switch schluessel {
        case "schritte": return Dauertext.ganzzahl(wert)
        case "strecke_km": return Dauertext.kilometer(wert)
        case "gehtempo_kmh": return komma(wert, stellen: 1) + " km/h"
        case "schrittlaenge_cm": return "\(Int(wert.rounded())) cm"
        case "pc_minuten", "schlaf_minuten", "unterwegs_minuten": return Dauertext.minuten(wert)
        case "gewicht_kg": return komma(wert, stellen: 1) + " kg"
        case "fahrten": return komma(wert, stellen: 1)
        case "kcal": return Dauertext.ganzzahl(wert) + " kcal"
        case "eiweiss_g", "kohlenhydrate_g", "fett_g": return "\(Int(wert.rounded())) g"
        case "internet_mb": return wert >= 1000 ? komma(wert / 1000, stellen: 1) + " GB" : "\(Int(wert.rounded())) MB"
        default: return komma(wert, stellen: 1)
        }
    }

    /// „↑ 14 %“, „↓ 23 %“, „gleich“; ohne Prozent (Vorperiode 0) der Unterschied in der Einheit.
    static func vergleich(_ vergleich: Rueckblick.Vergleich?, schluessel: String) -> String? {
        guard let vergleich else { return nil }
        if let prozent = vergleich.prozent {
            let ganz = Int(prozent.rounded())
            if ganz == 0 { return "gleich" }
            return (ganz > 0 ? "↑ " : "↓ ") + "\(abs(ganz)) %"
        }
        if vergleich.differenz == 0 { return "gleich" }
        return (vergleich.differenz > 0 ? "↑ " : "↓ ") + wert(abs(vergleich.differenz), schluessel: schluessel)
    }

    /// „Vorwoche Ø 8.799“ oder „Vorwoche: keine Daten“.
    static func vorher(_ wert: Rueckblick.Wert, schluessel: String, vorperiode: String) -> String {
        guard let schnitt = wert.schnitt, wert.tage > 0 else { return "\(vorperiode): keine Daten" }
        return "\(vorperiode) Ø \(self.wert(schnitt, schluessel: schluessel))"
    }

    /// „+12 kcal“, „−217 kcal“, „±0 kcal“.
    static func mitVorzeichen(_ wert: Double, einheit: String) -> String {
        let ganz = Int(wert.rounded())
        return (ganz > 0 ? "+" : ganz < 0 ? "−" : "±") + Dauertext.ganzzahl(Double(abs(ganz))) + " " + einheit
    }

    static func komma(_ wert: Double, stellen: Int) -> String {
        String(format: "%.\(stellen)f", wert).replacingOccurrences(of: ".", with: ",")
    }

    /// „KW 11 · 9.–15. März 2026“, „KW 14 · 30. März – 5. April 2026“ oder „März 2026“.
    static func zeitraum(art: String, von: String, bis: String) -> String {
        guard let anfang = Gewichtsverlauf.datum(von), let ende = Gewichtsverlauf.datum(bis) else { return "\(von) – \(bis)" }
        var kalender = Calendar(identifier: .iso8601)
        kalender.locale = deutsch
        let monat = DateFormatter()
        monat.locale = deutsch
        if art == "monat" {
            monat.dateFormat = "LLLL yyyy"
            return monat.string(from: anfang)
        }
        let woche = kalender.component(.weekOfYear, from: anfang)
        let tagA = kalender.component(.day, from: anfang), tagB = kalender.component(.day, from: ende)
        let jahr = kalender.component(.year, from: ende)
        monat.dateFormat = "LLLL"
        if kalender.component(.month, from: anfang) == kalender.component(.month, from: ende) {
            return "KW \(woche) · \(tagA).–\(tagB). \(monat.string(from: ende)) \(jahr)"
        }
        return "KW \(woche) · \(tagA). \(monat.string(from: anfang)) – \(tagB). \(monat.string(from: ende)) \(jahr)"
    }

    /// „1 Tag“, „5 Tagen“ (nach „von“).
    static func tage(_ anzahl: Int) -> String { anzahl == 1 ? "1 Tag" : "\(anzahl) Tagen" }
}

extension Rueckblick {
    /// Ausgedachter Zeitraum für den Demo-Modus.
    static func demo(art: String, heute: String = Kalendertag.heute()) -> Rueckblick {
        func wert(_ schnitt: Double?, _ tage: Int) -> Wert {
            Wert(summe: schnitt.map { $0 * Double(tage) }, schnitt: schnitt, tage: schnitt == nil ? 0 : tage)
        }
        func zahl(_ s: String, _ name: String, _ jetzt: Double, _ vorher: Double, bereich: String) -> Kennzahl {
            Kennzahl(schluessel: s, name: name, einheit: "", bereich: bereich, jetzt: wert(jetzt, 7), vorher: wert(vorher, 7),
                     vergleich: Vergleich(differenz: jetzt - vorher, prozent: ((jetzt - vorher) / vorher * 100).rounded()))
        }
        let von = Kalendertag.verschoben(heute, um: art == "monat" ? -29 : -6)
        let abschnitt = Abschnitt(von: von, bis: heute,
                                  orte: [.init(name: "Zuhause", minuten: 6100), .init(name: "Arbeit", minuten: 2800),
                                         .init(name: "Bäcker", minuten: 120)],
                                  orteAnzahl: 3, neueOrte: [],
                                  fahrten: .init(anzahl: 14, minuten: 190, streckeKm: 34.9,
                                                 haeufigste: [.init(strecke: "Zuhause → Arbeit", anzahl: 5),
                                                              .init(strecke: "Arbeit → Zuhause", anzahl: 5)]))
        let zielJetzt = Essen.Ziel.Teil(tageMitZiel: 7, zielSchnittKcal: 2000, tageVollstaendig: 6, tageUnvollstaendig: 1,
                                         tageEssenOhneZiel: 0, abweichungSchnittKcal: -50, abweichungSchnittProzent: -2.5,
                                         tageImZielbereich: 4, anteilImZielbereichProzent: 67)
        let zielVorher = Essen.Ziel.Teil(tageMitZiel: 7, zielSchnittKcal: 2000, tageVollstaendig: 7, tageUnvollstaendig: 0,
                                          tageEssenOhneZiel: 0, abweichungSchnittKcal: 10, abweichungSchnittProzent: 0.5,
                                          tageImZielbereich: 5, anteilImZielbereichProzent: 71)
        return Rueckblick(
            art: art, von: von, bis: heute, tageGesamt: 7, tageAusgewertet: 7, laeuftNoch: false,
            kennzahlen: [
                zahl("schritte", "Schritte", 7300, 6900, bereich: "schritte"),
                zahl("strecke_km", "Strecke", 5.4, 5.1, bereich: "strecke"),
                zahl("schlaf_minuten", "Schlaf", 425, 431, bereich: "schlaf"),
                zahl("gewicht_kg", "Gewicht", 82.7, 83.1, bereich: "gewicht"),
                zahl("pc_minuten", "PC-Zeit", 118, 131, bereich: "pc"),
                zahl("unterwegs_minuten", "Unterwegs", 480, 455, bereich: "standort"),
                zahl("fahrten", "Fahrten", 2, 2.3, bereich: "standort"),
                zahl("kcal", "Energie", 1950, 2010, bereich: "essen"),
                zahl("eiweiss_g", "Eiweiß", 92, 88, bereich: "essen"),
            ],
            gewicht: Gewicht(messungen: 3, messungenVorher: 2, veraenderung: .init(kg: -0.4)),
            jetzt: abschnitt, vorher: abschnitt,
            pc: Pc(fehler: nil, tage: 7, kategorien: [
                .init(name: "Programmieren", jetzt: wert(45, 7), vorher: wert(52, 7), vergleich: .init(differenz: -7, prozent: -13)),
                .init(name: "Surfen", jetzt: wert(30, 7), vorher: wert(28, 7), vergleich: .init(differenz: 2, prozent: 7)),
            ]),
            essen: Essen(fenster: .init(jetzt: .init(tage: 7, erste: "07:40", letzte: "19:55"),
                                        vorher: .init(tage: 7, erste: "08:05", letzte: "20:20")),
                         ziel: .init(zielbereichProzent: 10, jetzt: zielJetzt, vorher: zielVorher)),
            zurueck: Kalendertag.verschoben(von, um: art == "monat" ? -30 : -7),
            weiter: Kalendertag.verschoben(heute, um: 1))
    }
}
