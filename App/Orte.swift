import Foundation

/// GET /api/dashboard/karte: Aufenthalte und Fahrten eines Tages. Die Punkte für die Karte liest die Kartenseite
/// des Servers selbst.
struct Ortstag: Codable, Equatable {
    struct Aufenthalt: Codable, Equatable, Identifiable {
        var ort: String
        var beginn: String
        var ende: String
        var minuten: Double?
        /// Ein Ort, der zum ersten Mal vorkommt und noch keinen Namen hat.
        var neu: Bool?
        /// Kein echter Aufenthalt, sondern eine Zeit ohne Standortpunkte.
        var luecke: Bool?
        /// Mitte des Aufenthalts.
        var lat: Double?
        var lon: Double?

        var id: String { "\(beginn)|\(ort)" }
    }

    struct Fahrt: Codable, Equatable, Identifiable {
        var kennung: String
        var start: String
        var ziel: String
        var abfahrt: String
        var ankunft: String
        var dauerMin: Double?
        var streckeKm: Double?
        var korrigiert: Bool?

        var id: String { kennung }

        enum CodingKeys: String, CodingKey {
            case kennung, start, ziel, abfahrt, ankunft, korrigiert
            case dauerMin = "dauer_min"
            case streckeKm = "strecke_km"
        }
    }

    /// Eine Zeile im Ablauf des Tages: ein Ort oder eine Fahrt, nach der Uhrzeit sortiert.
    enum Schritt: Identifiable, Equatable {
        case ort(Aufenthalt)
        case fahrt(Fahrt)

        var id: String {
            switch self {
            case .ort(let aufenthalt): return "ort|" + aufenthalt.id
            case .fahrt(let fahrt): return "fahrt|" + fahrt.id
            }
        }

        var beginn: Date? {
            switch self {
            case .ort(let aufenthalt): return Zeitpunkt.lesen(aufenthalt.beginn)
            case .fahrt(let fahrt): return Zeitpunkt.lesen(fahrt.abfahrt)
            }
        }
    }

    var tag: String
    var aufenthalte: [Aufenthalt]
    var routen: [Fahrt]

    /// Orte und Fahrten nach der Uhrzeit. Lücken ohne Standortpunkte bleiben draußen: Sie sind kein Ort.
    var ablauf: [Schritt] {
        let schritte = aufenthalte.filter { $0.luecke != true }.map(Schritt.ort) + routen.map(Schritt.fahrt)
        return schritte.sorted { ($0.beginn ?? .distantPast) < ($1.beginn ?? .distantPast) }
    }

    /// Ausgedachte Daten für die Demo.
    static func demo(tag: String) -> Ortstag {
        func zeit(_ stunde: Int, _ minute: Int) -> String {
            let datum = Gewichtsverlauf.datum(tag) ?? Date()
            let wann = Calendar.current.date(bySettingHour: stunde, minute: minute, second: 0, of: datum) ?? datum
            return Zeitpunkt.text(wann)
        }
        return Ortstag(tag: tag, aufenthalte: [
            Aufenthalt(ort: "Zuhause", beginn: zeit(0, 0), ende: zeit(8, 10), minuten: 490),
            Aufenthalt(ort: "Arbeit", beginn: zeit(8, 35), ende: zeit(16, 50), minuten: 495),
            Aufenthalt(ort: "Supermarkt", beginn: zeit(17, 5), ende: zeit(17, 30), minuten: 25, neu: true),
            Aufenthalt(ort: "Zuhause", beginn: zeit(17, 45), ende: zeit(23, 59), minuten: 374),
        ], routen: [
            Fahrt(kennung: "demo-1", start: "Zuhause", ziel: "Arbeit", abfahrt: zeit(8, 10), ankunft: zeit(8, 35),
                  dauerMin: 25, streckeKm: 18.4),
            Fahrt(kennung: "demo-2", start: "Arbeit", ziel: "Supermarkt", abfahrt: zeit(16, 50), ankunft: zeit(17, 5),
                  dauerMin: 15, streckeKm: 9.1),
            Fahrt(kennung: "demo-3", start: "Supermarkt", ziel: "Zuhause", abfahrt: zeit(17, 30), ankunft: zeit(17, 45),
                  dauerMin: 15, streckeKm: 8.7),
        ])
    }
}

/// Zeitpunkte des Servers, etwa `2026-03-14T09:55:49.263831Z`. Die Nachkommastellen der Sekunden fallen weg.
enum Zeitpunkt {
    static func lesen(_ text: String) -> Date? {
        var rein = text
        if let punkt = rein.firstIndex(of: "."),
           let ende = rein[punkt...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            rein.removeSubrange(punkt..<ende)
        }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: rein)
    }

    static func text(_ datum: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: datum)
    }

    /// „8:10–16:50“, über Mitternacht „bis 9:56“ bzw. „ab 13:07“.
    static func spanne(_ beginn: String, _ ende: String, tag: String, kalender: Calendar = .current) -> String {
        guard let von = lesen(beginn), let bis = lesen(ende) else { return "" }
        let uhr = { (datum: Date) in datum.formatted(date: .omitted, time: .shortened) }
        let tagDatum = Gewichtsverlauf.datum(tag)
        let vorher = tagDatum.map { kalender.startOfDay(for: von) < kalender.startOfDay(for: $0) } ?? false
        let nachher = tagDatum.map { kalender.startOfDay(for: bis) > kalender.startOfDay(for: $0) } ?? false
        switch (vorher, nachher) {
        case (true, true): return "ganzer Tag"
        case (true, false): return "bis \(uhr(bis))"
        case (false, true): return "ab \(uhr(von))"
        case (false, false): return "\(uhr(von))–\(uhr(bis))"
        }
    }
}
