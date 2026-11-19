import CoreLocation
import Foundation

/// Eine Fahrt, wie die App sie selbst erkannt hat. Sie ist sofort sichtbar, auch wenn der Server unterwegs nicht
/// erreichbar ist. Ausgewertet (welcher Ort, Name, Strecke auf den Straßen) wird weiter am Server; das hier ist nur
/// der vorläufige Stand, bis die Punkte dort angekommen sind.
struct LokaleFahrt: Codable, Equatable, Identifiable {
    var id: String
    var beginn: Date
    /// Zeit der letzten Bewegung: solange die Fahrt läuft, „bis jetzt“, danach die Ankunft.
    var ende: Date?
    var startLat: Double?
    var startLon: Double?
    /// Wo sich das iPhone zuletzt bewegt hat, am Ende also das Ziel.
    var zielLat: Double?
    var zielLon: Double?
    /// Summe der Abstände zwischen den aufgezeichneten Punkten.
    var meter: Double = 0
    /// Letzter Punkt der Spur, für den nächsten Abstand.
    var spurLat: Double?
    var spurLon: Double?
    var laeuft: Bool

    var minuten: Double? {
        ende.map { max(0, $0.timeIntervalSince(beginn) / 60) }
    }
}

/// Ein erkannter Ort vom Server (`GET /api/orte`). Die App merkt sich die Liste, damit sie Start und Ziel ihrer
/// eigenen Fahrten auch unterwegs benennen kann.
struct BekannterOrt: Codable, Equatable {
    var name: String
    var lat: Double
    var lon: Double
    /// Nummer des eigenen Namens; ohne ist der Name automatisch („Ort 12“) oder kommt von „Zuhause“ bzw. einer Region.
    var nameId: Int?
    var benannt: Bool?
    var automatischerName: String?

    enum CodingKeys: String, CodingKey {
        case name, lat, lon, benannt
        case nameId = "name_id"
        case automatischerName = "automatischer_name"
    }
}

/// Eigener Name (`GET /api/orte/namen`). `orte` = wie viele erkannte Orte ihn gerade tragen.
struct Ortsname: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    var lat: Double
    var lon: Double
    var orte: Int?
}

/// Ausgeblendete Stelle, „Kein Halt“ (`GET /api/orte/ausgeblendet`).
struct AusgeblendeterOrt: Codable, Equatable, Identifiable {
    var id: Int
    var bezeichnung: String
    var lat: Double
    var lon: Double
    var erstelltAm: String?

    enum CodingKeys: String, CodingKey {
        case id, bezeichnung, lat, lon
        case erstelltAm = "erstellt_am"
    }
}

/// Die Regeln des Fahrtenbuchs, ohne Speicher, damit sie sich testen lassen.
enum Fahrtregel {
    /// Wie am Server (`ORTE_RADIUS_M`): So nah muss eine Stelle an der Mitte eines Orts liegen.
    static let ortRadius = 150.0
    /// So lange hebt die App ihre eigenen Fahrten auf; danach kennt sie der Server längst.
    static let aufheben: TimeInterval = 3 * 24 * 3600
    /// Kürzer zählt nicht: eine Probe, die gerade so Fahrtempo erreicht hat.
    static let mindestMeter = 300.0
    /// Spielraum beim Vergleich mit den Zeiten des Servers.
    static let spielraum: TimeInterval = 2 * 60

    static func abstand(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        CLLocation(latitude: lat1, longitude: lon1).distance(from: CLLocation(latitude: lat2, longitude: lon2))
    }

    /// Name des nächsten bekannten Orts im Umkreis, sonst nil.
    static func ortsname(lat: Double?, lon: Double?, orte: [BekannterOrt]) -> String? {
        guard let lat, let lon else { return nil }
        return orte
            .map { (abstand(lat, lon, $0.lat, $0.lon), $0.name) }
            .filter { $0.0 <= ortRadius }
            .min { $0.0 < $1.0 }?.1
    }

    /// Die eigenen Fahrten eines Tages, die der Server noch nicht ausgewertet hat: Sie beginnen nach seinem letzten
    /// bekannten Zeitpunkt des Tages und überschneiden sich mit keiner seiner Fahrten. Sobald die Punkte angekommen
    /// sind, zeigt der Server sie selbst (mit Namen und Strecke), und sie verschwinden hier.
    static func offen(_ fahrten: [LokaleFahrt], server: Ortstag?, tag: String,
                      kalender: Calendar = .current) -> [LokaleFahrt] {
        guard let tagDatum = Gewichtsverlauf.datum(tag) else { return [] }
        let amTag = fahrten.filter { kalender.isDate($0.beginn, inSameDayAs: tagDatum) }
        guard let server else { return amTag.sorted { $0.beginn < $1.beginn } }
        let zeiten = server.aufenthalte.compactMap { Zeitpunkt.lesen($0.ende) }
            + server.routen.compactMap { Zeitpunkt.lesen($0.ankunft) }
        let serverBis = zeiten.max() ?? .distantPast
        let serverFahrten = server.routen.compactMap { fahrt -> (Date, Date)? in
            guard let von = Zeitpunkt.lesen(fahrt.abfahrt), let bis = Zeitpunkt.lesen(fahrt.ankunft) else { return nil }
            return (von, bis)
        }
        return amTag.filter { eigene in
            let bis = eigene.ende ?? eigene.beginn
            let ueberschneidet = serverFahrten.contains { von, ende in
                eigene.beginn < ende.addingTimeInterval(spielraum) && bis > von.addingTimeInterval(-spielraum)
            }
            return eigene.beginn > serverBis.addingTimeInterval(-spielraum) && !ueberschneidet
        }
        .sorted { $0.beginn < $1.beginn }
    }
}

/// Die Fahrten, die die App selbst erkannt hat, auf dem iPhone gespeichert (nur die letzten Tage).
@MainActor
final class Fahrtenbuch: ObservableObject {
    static let shared = Fahrtenbuch(datei: Warteschlange.shared.ordner.appendingPathComponent("fahrtenbuch.json"))

    @Published private(set) var fahrten: [LokaleFahrt] = []
    private let datei: URL
    private var ungesichert = 0

    init(datei: URL, jetzt: Date = Date()) {
        self.datei = datei
        if let daten = try? Data(contentsOf: datei),
           let alt = try? JSONDecoder().decode([LokaleFahrt].self, from: daten) {
            fahrten = alt.filter { jetzt.timeIntervalSince($0.beginn) < Fahrtregel.aufheben }
        }
    }

    /// Eine Fahrt beginnt. `ort`: wo das iPhone vor dem Aufbruch war.
    func beginnen(_ zeit: Date, ort: CLLocation?) {
        // Eine noch offene Fahrt (App beendet, iPhone neu gestartet) gilt als zu Ende.
        for i in fahrten.indices where fahrten[i].laeuft { fahrten[i].laeuft = false }
        fahrten.removeAll { zeit.timeIntervalSince($0.beginn) >= Fahrtregel.aufheben }
        fahrten.append(LokaleFahrt(
            id: UUID().uuidString, beginn: zeit, ende: zeit,
            startLat: ort?.coordinate.latitude, startLon: ort?.coordinate.longitude,
            zielLat: ort?.coordinate.latitude, zielLon: ort?.coordinate.longitude,
            spurLat: ort?.coordinate.latitude, spurLon: ort?.coordinate.longitude, laeuft: true))
        sichern()
    }

    /// Ein Punkt während der Fahrt. `ziel`: wo sich das iPhone zuletzt bewegt hat, `bewegt`: wann.
    func punkt(_ ort: CLLocation, ziel: CLLocation, bewegt: Date) {
        guard let i = fahrten.lastIndex(where: \.laeuft) else { return }
        let lat = ort.coordinate.latitude, lon = ort.coordinate.longitude
        if let spurLat = fahrten[i].spurLat, let spurLon = fahrten[i].spurLon {
            fahrten[i].meter += Fahrtregel.abstand(spurLat, spurLon, lat, lon)
        }
        if fahrten[i].startLat == nil {
            fahrten[i].startLat = lat
            fahrten[i].startLon = lon
        }
        fahrten[i].spurLat = lat
        fahrten[i].spurLon = lon
        fahrten[i].zielLat = ziel.coordinate.latitude
        fahrten[i].zielLon = ziel.coordinate.longitude
        fahrten[i].ende = max(fahrten[i].ende ?? bewegt, bewegt)
        ungesichert += 1
        if ungesichert >= 20 { sichern() }
    }

    /// Die Fahrt ist zu Ende. Sehr kurze fallen weg (eine Probe, kein Weg).
    func beenden() {
        guard let i = fahrten.lastIndex(where: \.laeuft) else { return }
        fahrten[i].laeuft = false
        if fahrten[i].meter < Fahrtregel.mindestMeter { fahrten.remove(at: i) }
        sichern()
    }

    private func sichern() {
        ungesichert = 0
        if let daten = try? JSONEncoder().encode(fahrten) {
            try? daten.write(to: datei, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
