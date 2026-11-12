import Foundation
import UIKit

/// Foto oder Text, das der Server angenommen hat und Claude noch schätzt.
struct Analyse: Codable, Equatable, Identifiable {
    var auftrag: Int
    var titel: String
    var status: String
    var fehler: String?

    var id: Int { auftrag }
    var laeuft: Bool { status == "wartet" || status == "laeuft" }
}

/// Jede Erfassung landet zuerst hier und wird dann gesendet. Ein Eintrag verschwindet erst,
/// wenn der Server ihn bestätigt hat. Liegt in einem App-Ordner, der nicht in iPhone-Sicherungen kommt.
@MainActor
final class Warteschlange: ObservableObject {
    static let shared = Warteschlange()

    /// So lange nach der ersten Erfassung kann Weiteres „zur letzten Mahlzeit“ dazukommen (Grenze des Servers).
    static let fensterLetzte: TimeInterval = 30 * 60

    struct Letzte: Codable, Equatable {
        var id: String
        var zeit: Date
    }

    private struct Ablage: Codable {
        var eintraege: [Eintrag]
        var analysen: [Analyse]
        var letzte: Letzte?
    }

    @Published private(set) var eintraege: [Eintrag] = []
    @Published private(set) var analysen: [Analyse] = []
    @Published private(set) var sendet = false
    /// Hinweis für den Menschen, etwa „neu koppeln“.
    @Published var meldung: String?
    /// Ändert sich, sobald der Server etwas Neues hat: Die Anzeige des Tages lädt dann neu.
    @Published private(set) var neuesAmServer = 0
    private(set) var letzte: Letzte?

    let ordner: URL
    /// Für Tests: ersetzt den gekoppelten Server.
    var apiQuelle: () -> Api? = { AppZustand.gespeicherteApi() }
    var zustimmungQuelle: () -> Zustimmung = { Zustimmung.gespeichert }

    init(ordner: URL? = nil) {
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var ziel = ordner ?? basis.appendingPathComponent("Warteschlange", isDirectory: true)
        try? FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        var werte = URLResourceValues()
        werte.isExcludedFromBackup = true
        try? ziel.setResourceValues(werte)
        self.ordner = ziel
        if let daten = try? Data(contentsOf: standDatei),
           let alt = try? Self.dekodierer.decode(Ablage.self, from: daten) {
            eintraege = alt.eintraege
            analysen = alt.analysen
            letzte = alt.letzte
        }
    }

    private static let kodierer: JSONEncoder = {
        let kodierer = JSONEncoder()
        kodierer.dateEncodingStrategy = .secondsSince1970
        return kodierer
    }()

    private static let dekodierer: JSONDecoder = {
        let dekodierer = JSONDecoder()
        dekodierer.dateDecodingStrategy = .secondsSince1970
        return dekodierer
    }()

    private var standDatei: URL { ordner.appendingPathComponent("stand.json") }

    private func bildDatei(_ id: String) -> URL { ordner.appendingPathComponent("\(id).jpg") }

    /// Auch bei gesperrtem iPhone les- und schreibbar, sobald es einmal entsperrt war.
    private func schreiben(_ daten: Data, nach datei: URL) throws {
        try daten.write(to: datei, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func speichern() {
        let ablage = Ablage(eintraege: eintraege, analysen: analysen, letzte: letzte)
        if let daten = try? Self.kodierer.encode(ablage) {
            try? schreiben(daten, nach: standDatei)
        }
    }

    // MARK: Aufnehmen

    /// Gibt es eine Mahlzeit aus den letzten 30 Minuten, zu der etwas dazukommen kann?
    func letzteMoeglich(jetzt: Date = Date()) -> Bool {
        guard let letzte else { return false }
        let alter = jetzt.timeIntervalSince(letzte.zeit)
        return alter >= 0 && alter < Self.fensterLetzte
    }

    /// `zurLetzten`: kommt zur vorigen Mahlzeit dazu, statt eine neue anzulegen.
    func aufnehmen(_ neu: Eintrag, bild: Data? = nil, zurLetzten: Bool = false) throws {
        var eintrag = neu
        if eintrag.art == .foto {
            guard let bild, !bild.isEmpty else { throw EintragFehler.fotoFehlt }
            try schreiben(bild, nach: bildDatei(eintrag.id))
        }
        if zurLetzten, letzteMoeglich(jetzt: eintrag.zeit), let letzte {
            eintrag.gehoertZu = letzte.id
        } else {
            letzte = Letzte(id: eintrag.id, zeit: eintrag.zeit)
        }
        eintraege.append(eintrag)
        speichern()
    }

    func loeschen(_ id: String) {
        eintraege.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: bildDatei(id))
        speichern()
    }

    /// Fehlgeschlagenen Eintrag wieder einreihen.
    func erneut(_ id: String) {
        aendern(id) { eintrag in
            eintrag.stand = .wartet
            eintrag.hinweis = nil
            eintrag.naechsterVersuch = nil
        }
    }

    func analyseAusblenden(_ auftrag: Int) {
        analysen.removeAll { $0.auftrag == auftrag }
        speichern()
    }

    private func aendern(_ id: String, _ aenderung: (inout Eintrag) -> Void) {
        guard let stelle = eintraege.firstIndex(where: { $0.id == id }) else { return }
        aenderung(&eintraege[stelle])
        speichern()
    }

    var wartend: Int { eintraege.filter { $0.stand == .wartet }.count }

    // MARK: Senden

    /// Sendet, was dran ist. `alle`: auch Einträge, deren Wartezeit noch läuft (Knopf „Jetzt senden“).
    func senden(alle: Bool = false) async {
        guard !sendet, wartend > 0 else { return }
        guard let api = apiQuelle() else { return }
        sendet = true
        // Bittet iOS um etwas Zeit, falls die App währenddessen verlassen wird.
        hintergrund = UIApplication.shared.beginBackgroundTask(withName: "Warteschlange") { [weak self] in
            Task { @MainActor in self?.hintergrundBeenden() }
        }
        defer {
            sendet = false
            hintergrundBeenden()
        }
        let zugestimmt = zustimmungQuelle() == .ja
        for id in eintraege.map(\.id) {
            guard let eintrag = eintraege.first(where: { $0.id == id }), eintrag.stand == .wartet else { continue }
            if !alle, let wann = eintrag.naechsterVersuch, wann > Date() { continue }
            if eintrag.brauchtZustimmung && !zugestimmt {
                aendern(id) { $0.hinweis = "Wartet auf deine Zustimmung zur Fotoanalyse (Einstellungen)." }
                continue
            }
            let anfrage: Anfrage
            do {
                var bild: Data?
                if eintrag.art == .foto { bild = try? Data(contentsOf: bildDatei(id)) }
                anfrage = try eintrag.anfrage(bild: bild)
            } catch {
                aendern(id) { eintrag in
                    eintrag.stand = .fehlgeschlagen
                    eintrag.hinweis = "Das Foto ist nicht mehr da."
                }
                continue
            }
            do {
                let (status, daten) = try await api.senden(anfrage)
                switch Ergebnis.bewerten(status: status, art: eintrag.art) {
                case .erledigt:
                    erledigt(eintrag, daten)
                case .neuKoppeln:
                    meldung = "Der Server kennt diese App nicht mehr. Bitte neu koppeln, die Einträge bleiben erhalten."
                    return
                case .fehlgeschlagen(let hinweis):
                    let detail = Api.fehlertext(daten)
                    aendern(id) { eintrag in
                        eintrag.stand = .fehlgeschlagen
                        eintrag.hinweis = hinweis ?? (detail.isEmpty ? "Der Server lehnt den Eintrag ab [\(status)]." : "\(detail) [\(status)]")
                    }
                case .spaeter:
                    spaeter(id, "Server gerade nicht bereit [\(status)]")
                }
            } catch {
                // Keine Verbindung: Die übrigen Einträge kämen auch nicht durch.
                spaeter(id, Server.beschreibung(error))
                return
            }
        }
        meldung = nil
    }

    private var hintergrund = UIBackgroundTaskIdentifier.invalid

    private func hintergrundBeenden() {
        guard hintergrund != .invalid else { return }
        UIApplication.shared.endBackgroundTask(hintergrund)
        hintergrund = .invalid
    }

    private func spaeter(_ id: String, _ grund: String) {
        aendern(id) { eintrag in
            eintrag.versuche += 1
            eintrag.naechsterVersuch = Date().addingTimeInterval(Ergebnis.wartezeit(versuche: eintrag.versuche))
            eintrag.hinweis = grund
        }
    }

    private func erledigt(_ eintrag: Eintrag, _ daten: Data) {
        eintraege.removeAll { $0.id == eintrag.id }
        try? FileManager.default.removeItem(at: bildDatei(eintrag.id))
        if eintrag.brauchtZustimmung,
           let antwort = try? JSONDecoder().decode(Sendeantwort.self, from: daten), let auftrag = antwort.id,
           !analysen.contains(where: { $0.auftrag == auftrag }) {
            analysen.append(Analyse(auftrag: auftrag, titel: eintrag.titel, status: antwort.status ?? "wartet"))
        }
        neuesAmServer += 1
        speichern()
    }

    // MARK: Stand der Analysen

    /// Fragt nach, was aus den gesendeten Fotos und Texten geworden ist.
    func analysenPruefen() async {
        guard analysen.contains(where: \.laeuft), let api = apiQuelle() else { return }
        for analyse in analysen where analyse.laeuft {
            do {
                let stand = try await api.lesen(Auftragsstand.self, "GET", "/api/essen/foto/\(analyse.auftrag)")
                guard let stelle = analysen.firstIndex(where: { $0.auftrag == analyse.auftrag }) else { continue }
                switch stand.status {
                case "fertig", "geloescht":
                    analysen.remove(at: stelle)
                    neuesAmServer += 1
                default:
                    analysen[stelle].status = stand.status
                    analysen[stelle].fehler = stand.fehler
                }
            } catch ApiFehler.status(404, _) {
                analysen.removeAll { $0.auftrag == analyse.auftrag }
            } catch {
                break
            }
        }
        speichern()
    }

    // MARK: Zwischenspeicher für die Anzeige ohne Server

    func merken<T: Encodable>(_ wert: T, als name: String) {
        if let daten = try? JSONEncoder().encode(wert) {
            try? schreiben(daten, nach: ordner.appendingPathComponent("\(name).json"))
        }
    }

    /// Gemerkter Wert und wann er gespeichert wurde.
    func gemerkt<T: Decodable>(_ typ: T.Type, _ name: String) -> (T, Date)? {
        let datei = ordner.appendingPathComponent("\(name).json")
        guard let daten = try? Data(contentsOf: datei),
              let wert = try? JSONDecoder().decode(typ, from: daten) else { return nil }
        let werte = try? datei.resourceValues(forKeys: [.contentModificationDateKey])
        return (wert, werte?.contentModificationDate ?? Date())
    }
}
