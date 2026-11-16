import SwiftUI

/// GET /api/dashboard/verlauf, nur die Teile für Gesundheit und PC-Zeit.
struct Tagesverlauf: Codable, Equatable {
    struct Tag: Codable, Equatable, Identifiable {
        struct Schlaf: Codable, Equatable {
            var minuten: Double?
        }

        var tag: String
        var schritte: Double?
        /// Minuten je Rechner. Ohne PC-Daten leer.
        var pcMinuten: [String: Double]?
        var strecke: Double?
        var stockwerke: Double?
        var gehtempo: Double?
        var schrittlaenge: Double?
        var schlaf: Schlaf?

        var id: String { tag }

        enum CodingKeys: String, CodingKey {
            case tag, schritte, stockwerke, schlaf
            case pcMinuten = "pc_minuten"
            case strecke = "strecke_km"
            case gehtempo = "gehtempo_kmh"
            case schrittlaenge = "schrittlaenge_cm"
        }
    }

    struct Trend: Codable, Equatable {
        struct Vergleich: Codable, Equatable {
            var text: String?
        }

        var schluessel: String
        /// Mittel über 7 Tage, ein Wert je Tag des Zeitraums; null, wo zu wenige Tage Daten haben.
        var gleitend: [Double?]
        var vergleich: Vergleich?
    }

    struct Trends: Codable, Equatable {
        var kennzahlen: [Trend]
    }

    var bis: String
    var tage: [Tag]
    var trends: Trends?

    /// Durchschnitt über die Tage mit Wert und deren Anzahl. Ohne Wert nil, nie 0.
    func schnitt(_ kennzahl: Kennzahl) -> (wert: Double, tage: Int)? {
        let werte = tage.compactMap { kennzahl.wert($0) }
        guard !werte.isEmpty else { return nil }
        return (werte.reduce(0, +) / Double(werte.count), werte.count)
    }

    func trend(_ kennzahl: Kennzahl) -> Trend? {
        guard let schluessel = kennzahl.trendSchluessel else { return nil }
        return trends?.kennzahlen.first { $0.schluessel == schluessel }
    }

    /// Ein Punkt der 7-Tage-Linie. `stueck` zählt hoch, wo die Linie aussetzt, damit Lücken Lücken bleiben.
    struct Linienpunkt: Identifiable, Equatable {
        var tag: String
        var wert: Double
        var stueck: Int

        var id: String { tag }
    }

    func linie(_ kennzahl: Kennzahl) -> [Linienpunkt] {
        guard let gleitend = trend(kennzahl)?.gleitend, gleitend.count == tage.count else { return [] }
        var punkte: [Linienpunkt] = []
        var stueck = 0
        var luecke = false
        for (stelle, wert) in gleitend.enumerated() {
            if let wert {
                if luecke && !punkte.isEmpty { stueck += 1 }
                luecke = false
                punkte.append(Linienpunkt(tag: tage[stelle].tag, wert: wert, stueck: stueck))
            } else {
                luecke = true
            }
        }
        return punkte
    }

    /// Ausgedachte Daten für die Demo.
    static func demo(tage anzahl: Int, heute: Date = Date()) -> Tagesverlauf {
        let kalender = Calendar.current
        var liste: [Tag] = []
        var schritte: [Double] = []
        for abstand in stride(from: anzahl - 1, through: 0, by: -1) {
            let datum = kalender.date(byAdding: .day, value: -abstand, to: heute) ?? heute
            let teile = kalender.dateComponents([.year, .month, .day], from: datum)
            let name = String(format: "%04d-%02d-%02d", teile.year ?? 0, teile.month ?? 0, teile.day ?? 0)
            let welle = sin(Double(abstand) * 0.9)
            let wert = (6500 + welle * 2200).rounded()
            schritte.append(wert)
            liste.append(Tag(tag: name, schritte: wert,
                             pcMinuten: abstand % 3 == 0 ? [:] : ["Demo-Rechner": (110 + welle * 50).rounded()],
                             strecke: wert / 1400, stockwerke: (9 + welle * 5).rounded(),
                             gehtempo: 4.8 + welle * 0.2, schrittlaenge: (72 + welle * 2).rounded(),
                             schlaf: Tag.Schlaf(minuten: (440 - welle * 40).rounded())))
        }
        let gleitend: [Double?] = schritte.indices.map { stelle in
            let fenster = schritte[max(0, stelle - 6)...stelle]
            return fenster.count < 4 ? nil : fenster.reduce(0, +) / Double(fenster.count)
        }
        let trend = Trend(schluessel: "schritte", gleitend: gleitend,
                          vergleich: .init(text: "Schritte: ausgedachte Werte der Demo, kein Vergleich."))
        return Tagesverlauf(bis: liste.last?.tag ?? "", tage: liste, trends: Trends(kennzahlen: [trend]))
    }
}

/// Eine Kennzahl der Auswertungen: wie sie heißt, aussieht und aus einem Tag gelesen wird.
enum Kennzahl: String, CaseIterable, Identifiable {
    case schritte, strecke, stockwerke, schlaf, gehtempo, schrittlaenge, pcZeit

    static let gesundheit: [Kennzahl] = [.schritte, .strecke, .stockwerke, .schlaf, .gehtempo, .schrittlaenge]

    var id: String { rawValue }

    var name: String {
        switch self {
        case .schritte: return "Schritte"
        case .strecke: return "Strecke"
        case .stockwerke: return "Stockwerke"
        case .schlaf: return "Schlaf"
        case .gehtempo: return "Gehtempo"
        case .schrittlaenge: return "Schrittlänge"
        case .pcZeit: return "PC-Zeit"
        }
    }

    var symbol: String {
        switch self {
        case .schritte: return "figure.walk"
        case .strecke: return "map"
        case .stockwerke: return "stairs"
        case .schlaf: return "bed.double.fill"
        case .gehtempo: return "speedometer"
        case .schrittlaenge: return "ruler"
        case .pcZeit: return "desktopcomputer"
        }
    }

    var farbe: Color {
        self == .pcZeit ? .pcZeit : .gesundheit
    }

    /// Unter diesem Namen führt der Server die Kennzahl in den Trends. Strecke und Stockwerke haben dort keinen.
    var trendSchluessel: String? {
        switch self {
        case .schritte: return "schritte"
        case .schlaf: return "schlaf_minuten"
        case .gehtempo: return "gehtempo_kmh"
        case .schrittlaenge: return "schrittlaenge_cm"
        case .pcZeit: return "pc_minuten"
        case .strecke, .stockwerke: return nil
        }
    }

    /// Gehtempo und Schrittlänge sind schon Durchschnitte eines Tages, die übrigen sind Summen.
    var jeTag: Bool {
        self != .gehtempo && self != .schrittlaenge
    }

    /// Einheit für die Achse des Diagramms.
    var achse: String {
        switch self {
        case .schritte: return "Schritte"
        case .strecke: return "km"
        case .stockwerke: return "Stockwerke"
        case .schlaf, .pcZeit: return "Stunden"
        case .gehtempo: return "km/h"
        case .schrittlaenge: return "cm"
        }
    }

    /// Der Wert eines Tages, nil ohne Daten.
    func wert(_ tag: Tagesverlauf.Tag) -> Double? {
        switch self {
        case .schritte: return tag.schritte
        case .strecke: return tag.strecke
        case .stockwerke: return tag.stockwerke
        case .schlaf: return tag.schlaf?.minuten
        case .gehtempo: return tag.gehtempo
        case .schrittlaenge: return tag.schrittlaenge
        case .pcZeit:
            guard let minuten = tag.pcMinuten, !minuten.isEmpty else { return nil }
            return minuten.values.reduce(0, +)
        }
    }

    /// Der Wert, wie er im Diagramm steht: Minuten als Stunden, alles andere unverändert.
    func imDiagramm(_ wert: Double) -> Double {
        self == .schlaf || self == .pcZeit ? wert / 60 : wert
    }

    /// „7.300“, „6,5 km“, „7 h 10 min“.
    func text(_ wert: Double) -> String {
        switch self {
        case .schritte, .stockwerke: return Dauertext.ganzzahl(wert)
        case .strecke: return Dauertext.kilometer(wert)
        case .schlaf, .pcZeit: return Dauertext.minuten(wert)
        case .gehtempo: return String(format: "%.1f km/h", wert).replacingOccurrences(of: ".", with: ",")
        case .schrittlaenge: return "\(Int(wert.rounded())) cm"
        }
    }

    /// „Ø 7.300 pro Tag an 28 Tagen“ für Kennzahlen ohne Vergleich vom Server.
    func schnittText(_ schnitt: (wert: Double, tage: Int)) -> String {
        let tage = schnitt.tage == 1 ? "an 1 Tag" : "an \(schnitt.tage) Tagen"
        return "\(name): Ø \(text(schnitt.wert))\(jeTag ? " pro Tag" : "") \(tage) mit Daten."
    }
}

/// GET /api/pc/kategorien
struct PcKategorien: Codable, Equatable {
    struct Kategorie: Codable, Equatable, Identifiable {
        var name: String
        var minuten: Double
        var anteil: Double?

        var id: String { name }
    }

    struct Geraet: Codable, Equatable, Identifiable {
        var name: String
        var minuten: Double

        var id: String { name }
    }

    struct Spiel: Codable, Equatable, Identifiable {
        var name: String
        var minuten: Double
        var tage: Int?

        var id: String { name }
    }

    var gesamtMinuten: Double?
    var kategorien: [Kategorie]
    var geraete: [Geraet]
    var spiele: [Spiel]

    enum CodingKeys: String, CodingKey {
        case kategorien, geraete, spiele
        case gesamtMinuten = "gesamt_minuten"
    }

    static let demo = PcKategorien(
        gesamtMinuten: 400,
        kategorien: [.init(name: "Programmieren", minuten: 220, anteil: 55), .init(name: "Surfen", minuten: 120, anteil: 30),
                     .init(name: "Spiele", minuten: 60, anteil: 15)],
        geraete: [.init(name: "Demo-Rechner", minuten: 400)],
        spiele: [.init(name: "Sternenfahrer", minuten: 60, tage: 1)])
}
