import CoreLocation
import Foundation

/// Ein Standortpunkt im Format von OwnTracks, wie der Server es bei `POST /api/owntracks` erwartet.
struct Standortpunkt: Codable, Equatable {
    var lat: Double
    var lon: Double
    /// Unix-Sekunden. Zwei Punkte in derselben Sekunde zählen am Server als einer.
    var tst: Int
    /// Genauigkeit in Metern.
    var acc: Int?
    /// Geschwindigkeit in km/h.
    var vel: Int?
    /// Höhe in Metern.
    var alt: Int?
    /// Richtung in Grad.
    var cog: Int?
    /// Auslöser: „v“ für einen von iOS erkannten Besuch (Ankunft oder Abfahrt).
    var t: String?
    /// Modus wie bei OwnTracks: 1 sparsam, 2 Fahrt.
    var m: Int?

    var json: [String: Any] {
        var inhalt: [String: Any] = ["_type": "location", "lat": lat, "lon": lon, "tst": tst]
        if let acc { inhalt["acc"] = acc }
        if let vel { inhalt["vel"] = vel }
        if let alt { inhalt["alt"] = alt }
        if let cog { inhalt["cog"] = cog }
        if let t { inhalt["t"] = t }
        if let m { inhalt["m"] = m }
        return inhalt
    }
}

/// Die Regeln der Aufzeichnung, ohne CoreLocation, damit sie sich testen lassen.
enum Standortregel {
    /// So viele Punkte gehen höchstens in eine Sendung.
    static let jeSendung = 500
    /// Mehr hebt die App nicht auf; die ältesten fallen dann weg.
    static let pufferHoechstens = 100_000
    /// Während einer Fahrt: frühestens nach so vielen Sekunden und Metern ein neuer Punkt.
    static let fahrtSekunden = 4.0
    static let fahrtMeter = 25.0
    /// Während einer Fahrt zählen nur Punkte, die mindestens so genau sind.
    static let fahrtGenauigkeit = 100.0
    /// Steht das iPhone so lange still, endet die Fahrt von selbst.
    static let stillstand: TimeInterval = 10 * 60
    /// Eine Fahrt endet spätestens nach dieser Zeit, falls das Beenden vergessen wird.
    static let fahrtHoechstens: TimeInterval = 8 * 3600

    static func aufnehmen(genauigkeit: Double, sekundenSeitLetztem: Double?, meterSeitLetztem: Double?,
                          fahrt: Bool) -> Bool {
        guard genauigkeit >= 0 else { return false }
        if let sekunden = sekundenSeitLetztem, sekunden < 1 { return false }
        guard fahrt else { return true }
        guard genauigkeit <= fahrtGenauigkeit else { return false }
        if let sekunden = sekundenSeitLetztem, sekunden < fahrtSekunden { return false }
        if let meter = meterSeitLetztem, meter < fahrtMeter { return false }
        return true
    }

    /// Ab diesem Tempo gilt eine Bewegung als Fahrt (Auto, aber auch Fahrrad und Bahn).
    static let fahrtempoKmh = 20.0
    /// Schneller ist ein Messfehler.
    static let hoechsttempoKmh = 250.0
    /// Kreis um den letzten Aufenthaltsort; beim Verlassen weckt iOS die App.
    static let zaunMeter = 150.0
    /// So lange misst die App nach dem Verlassen genau, ob daraus eine Fahrt wird.
    static let probeDauer: TimeInterval = 3 * 60
    /// Nach einer Probe ohne Fahrt frühestens dann die nächste, sonst liefe beim Spazieren dauernd das GPS.
    static let probePause: TimeInterval = 15 * 60

    /// Tempo in km/h: gemessen, wenn das iPhone eines liefert und der Ort genau genug ist, sonst aus zwei Punkten
    /// gerechnet. `nil`, wenn sich nichts Verlässliches sagen lässt.
    static func tempo(gemessen: Double, genauigkeit: Double, meter: Double?, sekunden: Double?) -> Double? {
        if gemessen >= 0, genauigkeit >= 0, genauigkeit <= fahrtGenauigkeit {
            return gemessen * 3.6
        }
        // Aus zwei Punkten nur, wenn sie weit genug auseinanderliegen, dass Messfehler keine Rolle spielen.
        guard let meter, let sekunden, sekunden >= 10, sekunden <= 900,
              genauigkeit >= 0, meter >= max(300, 2 * genauigkeit) else { return nil }
        return meter / sekunden * 3.6
    }

    static func istFahrtempo(_ kmh: Double?) -> Bool {
        guard let kmh else { return false }
        return kmh >= fahrtempoKmh && kmh <= hoechsttempoKmh
    }

    static func probeVorbei(seitBeginn: TimeInterval) -> Bool {
        seitBeginn >= probeDauer
    }

    static func probeErlaubt(seitLetzter: TimeInterval) -> Bool {
        seitLetzter >= probePause
    }

    static func fahrtZuEnde(seitBewegung: TimeInterval, seitBeginn: TimeInterval) -> Bool {
        seitBewegung >= stillstand || seitBeginn >= fahrtHoechstens
    }

    /// Nach einem misslungenen Senden (unterwegs ist der Server nicht erreichbar): 5, 10, 20, höchstens 30 Minuten warten.
    static func wartezeit(fehlversuche: Int) -> TimeInterval {
        guard fehlversuche > 0 else { return 0 }
        return min(300 * pow(2, Double(min(fehlversuche - 1, 6))), 1800)
    }

    static func koerper(_ punkte: [Standortpunkt]) throws -> Data {
        try JSONSerialization.data(withJSONObject: punkte.map(\.json), options: [.sortedKeys])
    }
}

/// Zeichnet den Standort auf und schickt ihn an den eigenen Server. Ersetzt die OwnTracks-App.
/// Im Alltag sparsam (iOS meldet größere Ortswechsel und Besuche), während einer Fahrt genau.
@MainActor
final class Standort: NSObject, ObservableObject {
    static let shared = Standort()

    private enum Ablage {
        static let an = "standort-an"
        static let fahrtSeit = "standort-fahrt-seit"
        static let ohneAutomatik = "standort-ohne-automatik"
    }

    private static let zaun = "letzter-ort"

    /// Was iOS erlaubt hat, für die Anzeige.
    enum Erlaubnis {
        case offen, immer, nurBeimVerwenden, abgelehnt
    }

    @Published private(set) var an = UserDefaults.standard.bool(forKey: Ablage.an)
    @Published private(set) var erlaubnis = Erlaubnis.offen
    @Published private(set) var fahrtSeit: Date?
    /// Fahrten selbst erkennen (ohne Kurzbefehl-Automation).
    @Published var automatisch = !UserDefaults.standard.bool(forKey: Ablage.ohneAutomatik) {
        didSet {
            UserDefaults.standard.set(!automatisch, forKey: Ablage.ohneAutomatik)
            if !automatisch { probeBeenden() }
        }
    }
    /// Läuft gerade die kurze genaue Messung, ob aus dem Aufbruch eine Fahrt wird?
    @Published private(set) var probeSeit: Date?
    @Published private(set) var wartend = 0
    @Published private(set) var zuletztGesendet: Date?
    @Published private(set) var fehler: String?

    private let dienst = CLLocationManager()
    private let datei: URL
    private var puffer: [Standortpunkt] = []
    private var ungesichert = 0
    private var letzterOrt: CLLocation?
    /// Der vorige Ort von iOS, auch wenn er nicht gespeichert wurde: für das Tempo.
    private var vorigerOrt: CLLocation?
    private var letzteProbe = Date.distantPast
    private var anker: CLLocation?
    private var letzteBewegung = Date()
    private var sendet = false
    private var fehlversuche = 0
    private var naechsterVersuch = Date.distantPast

    override init() {
        datei = Warteschlange.shared.ordner.appendingPathComponent("standort.json")
        super.init()
        if let daten = try? Data(contentsOf: datei),
           let alt = try? JSONDecoder().decode([Standortpunkt].self, from: daten) {
            puffer = alt
        }
        wartend = puffer.count
        let seit = UserDefaults.standard.double(forKey: Ablage.fahrtSeit)
        if seit > 0 { fahrtSeit = Date(timeIntervalSince1970: seit) }
        dienst.delegate = self
        erlaubnis = Self.erlaubnis(dienst.authorizationStatus)
    }

    private static func erlaubnis(_ status: CLAuthorizationStatus) -> Erlaubnis {
        switch status {
        case .authorizedAlways: return .immer
        case .authorizedWhenInUse: return .nurBeimVerwenden
        case .denied, .restricted: return .abgelehnt
        default: return .offen
        }
    }

    // MARK: Ein und aus

    func einschalten() {
        an = true
        UserDefaults.standard.set(true, forKey: Ablage.an)
        switch dienst.authorizationStatus {
        case .notDetermined:
            dienst.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // iOS fragt „immer“ erst im zweiten Schritt.
            dienst.requestAlwaysAuthorization()
        default:
            break
        }
        starten()
    }

    func ausschalten() {
        fahrtBeenden()
        probeBeenden()
        an = false
        UserDefaults.standard.set(false, forKey: Ablage.an)
        dienst.stopMonitoringSignificantLocationChanges()
        dienst.stopMonitoringVisits()
        for region in dienst.monitoredRegions { dienst.stopMonitoring(for: region) }
        sichern()
    }

    /// Beim Start der App (auch wenn iOS sie wegen eines Ortswechsels im Hintergrund weckt).
    func starten() {
        guard an, erlaubnis == .immer || erlaubnis == .nurBeimVerwenden else { return }
        dienst.allowsBackgroundLocationUpdates = true
        dienst.pausesLocationUpdatesAutomatically = false
        dienst.startMonitoringSignificantLocationChanges()
        dienst.startMonitoringVisits()
        if let fahrtSeit {
            if Standortregel.fahrtZuEnde(seitBewegung: 0, seitBeginn: Date().timeIntervalSince(fahrtSeit)) {
                fahrtBeenden()
            } else {
                genauAufzeichnen()
            }
        }
    }

    // MARK: Fahrt

    /// Genaue, laufende Aufzeichnung, etwa wenn sich das iPhone mit dem Auto verbindet.
    func fahrtStarten() {
        guard an else { return }
        if fahrtSeit == nil {
            // Aus einer Probe wird eine Fahrt: Sie zählt ab dem Beginn der Probe.
            let beginn = probeSeit ?? Date()
            probeSeit = nil
            fahrtSeit = beginn
            UserDefaults.standard.set(beginn.timeIntervalSince1970, forKey: Ablage.fahrtSeit)
        }
        genauAufzeichnen()
    }

    // MARK: Fahrten selbst erkennen

    /// iOS weckt die App, wenn das iPhone den Kreis um den letzten Aufenthaltsort verlässt.
    private func zaunSetzen(_ ort: CLLocation?) {
        guard an, automatisch, erlaubnis == .immer, let ort,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(center: ort.coordinate, radius: Standortregel.zaunMeter, identifier: Self.zaun)
        region.notifyOnExit = true
        region.notifyOnEntry = false
        dienst.startMonitoring(for: region)
    }

    /// Kurz genau messen: Wird daraus Fahrtempo, beginnt eine Fahrt, sonst endet die Probe von selbst.
    private func probeStarten() {
        guard an, automatisch, fahrtSeit == nil, probeSeit == nil,
              Standortregel.probeErlaubt(seitLetzter: Date().timeIntervalSince(letzteProbe)) else { return }
        probeSeit = Date()
        genauAufzeichnen()
    }

    private func probeBeenden() {
        guard probeSeit != nil else { return }
        probeSeit = nil
        letzteProbe = Date()
        if fahrtSeit == nil {
            dienst.stopUpdatingLocation()
            dienst.showsBackgroundLocationIndicator = false
        }
        sichern()
        zaunSetzen(vorigerOrt)
    }

    private func genauAufzeichnen() {
        letzteBewegung = Date()
        anker = nil
        dienst.desiredAccuracy = kCLLocationAccuracyBest
        dienst.distanceFilter = kCLDistanceFilterNone
        dienst.activityType = .automotiveNavigation
        dienst.showsBackgroundLocationIndicator = true
        dienst.startUpdatingLocation()
    }

    func fahrtBeenden() {
        guard fahrtSeit != nil else { return }
        fahrtSeit = nil
        UserDefaults.standard.removeObject(forKey: Ablage.fahrtSeit)
        dienst.stopUpdatingLocation()
        dienst.showsBackgroundLocationIndicator = false
        sichern()
        zaunSetzen(vorigerOrt)
        Task { await senden(sofort: true) }
    }

    // MARK: Punkte aufnehmen

    private func neuerOrt(_ ort: CLLocation) {
        guard an else { return }
        // Tempo gegen den vorigen Ort von iOS, nicht gegen den zuletzt gespeicherten.
        let kmh = Standortregel.tempo(
            gemessen: ort.speed, genauigkeit: ort.horizontalAccuracy,
            meter: vorigerOrt.map { ort.distance(from: $0) },
            sekunden: vorigerOrt.map { ort.timestamp.timeIntervalSince($0.timestamp) })
        if ort.horizontalAccuracy >= 0 { vorigerOrt = ort }
        if fahrtSeit == nil, automatisch {
            if Standortregel.istFahrtempo(kmh) {
                fahrtStarten()
            } else if let probeSeit, Standortregel.probeVorbei(seitBeginn: ort.timestamp.timeIntervalSince(probeSeit)) {
                probeBeenden()
            }
        }
        let genau = fahrtSeit != nil || probeSeit != nil
        let fahrt = fahrtSeit != nil
        if fahrt {
            // Bewegung erkennen, damit eine vergessene Fahrt von selbst endet.
            if anker == nil { anker = ort }
            if ort.speed > 1.5 || (anker.map { ort.distance(from: $0) > 50 } ?? false) {
                letzteBewegung = ort.timestamp
                anker = ort
            }
            if let fahrtSeit, Standortregel.fahrtZuEnde(seitBewegung: ort.timestamp.timeIntervalSince(letzteBewegung),
                                                        seitBeginn: ort.timestamp.timeIntervalSince(fahrtSeit)) {
                fahrtBeenden()
                return
            }
        }
        let sekunden = letzterOrt.map { ort.timestamp.timeIntervalSince($0.timestamp) }
        let meter = letzterOrt.map { ort.distance(from: $0) }
        guard Standortregel.aufnehmen(genauigkeit: ort.horizontalAccuracy, sekundenSeitLetztem: sekunden,
                                      meterSeitLetztem: meter, fahrt: genau) else { return }
        letzterOrt = ort
        // Im sparsamen Betrieb liegt der Kreis immer um den letzten bekannten Ort.
        if !genau { zaunSetzen(ort) }
        aufnehmen(Standortpunkt(
            lat: ort.coordinate.latitude, lon: ort.coordinate.longitude,
            tst: Int(ort.timestamp.timeIntervalSince1970),
            acc: Int(ort.horizontalAccuracy.rounded()),
            vel: ort.speed >= 0 ? Int((ort.speed * 3.6).rounded()) : nil,
            alt: ort.verticalAccuracy >= 0 ? Int(ort.altitude.rounded()) : nil,
            cog: ort.course >= 0 ? Int(ort.course.rounded()) : nil,
            t: nil, m: genau ? 2 : 1))
    }

    private func neuerBesuch(lat: Double, lon: Double, genauigkeit: Double, zeit: Date) {
        guard an, genauigkeit >= 0 else { return }
        aufnehmen(Standortpunkt(lat: lat, lon: lon, tst: Int(zeit.timeIntervalSince1970),
                                acc: Int(genauigkeit.rounded()), vel: nil, alt: nil, cog: nil, t: "v", m: 1))
    }

    private func aufnehmen(_ punkt: Standortpunkt) {
        if puffer.last?.tst == punkt.tst { return }
        puffer.append(punkt)
        if puffer.count > Standortregel.pufferHoechstens {
            puffer.removeFirst(puffer.count - Standortregel.pufferHoechstens)
        }
        wartend = puffer.count
        ungesichert += 1
        // Während einer Fahrt nicht bei jedem Punkt auf die Platte schreiben.
        if (fahrtSeit == nil && probeSeit == nil) || ungesichert >= 15 { sichern() }
        Task { await senden() }
    }

    private func sichern() {
        ungesichert = 0
        if let daten = try? JSONEncoder().encode(puffer) {
            try? daten.write(to: datei, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: Senden

    /// `sofort`: nicht auf die Wartezeit nach einem Fehlversuch achten (App geöffnet, Netz gewechselt, Knopf).
    func senden(sofort: Bool = false) async {
        guard !sendet, !puffer.isEmpty else { return }
        guard sofort || Date() >= naechsterVersuch else { return }
        guard let api = AppZustand.gespeicherteApi() else { return }
        sendet = true
        defer { sendet = false }
        // Während einer Fahrt höchstens einmal je Minute, sonst entstünde je Punkt eine Sendung.
        naechsterVersuch = Date().addingTimeInterval(fahrtSeit == nil ? 5 : 60)
        while !puffer.isEmpty {
            let teil = Array(puffer.prefix(Standortregel.jeSendung))
            do {
                let anfrage = Anfrage(pfad: "/api/owntracks", typ: "application/json",
                                      koerper: try Standortregel.koerper(teil))
                let (status, daten) = try await api.senden(anfrage, zeitlimit: 20)
                guard (200..<300).contains(status) else {
                    throw ApiFehler.status(status, Api.fehlertext(daten))
                }
                // Inzwischen können neue Punkte dazugekommen sein: nur die gesendeten entfernen.
                puffer.removeFirst(min(teil.count, puffer.count))
                wartend = puffer.count
                fehlversuche = 0
                fehler = nil
                zuletztGesendet = Date()
                sichern()
            } catch {
                fehlversuche += 1
                naechsterVersuch = Date().addingTimeInterval(Standortregel.wartezeit(fehlversuche: fehlversuche))
                if let abgelehnt = error as? ApiFehler, case .status = abgelehnt {
                    fehler = Api.text(error)
                } else {
                    fehler = nil  // Unterwegs ist der Server nicht erreichbar: kein Fehler, die Punkte warten.
                }
                return
            }
        }
    }
}

extension Standort: CLLocationManagerDelegate {
    // iOS ruft diese Methoden auf dem Hauptthread auf (dort wurde der Dienst angelegt). Übergeben werden nur Werte.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let orte = locations
        Task { @MainActor in
            for ort in orte { Standort.shared.neuerOrt(ort) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude
        let genauigkeit = visit.horizontalAccuracy
        // Bei der Ankunft steht die Abfahrt noch aus (ferne Zukunft), dann gilt die Ankunft.
        let zeit = visit.departureDate == Date.distantFuture ? visit.arrivalDate : visit.departureDate
        guard zeit != Date.distantPast else { return }
        Task { @MainActor in
            Standort.shared.neuerBesuch(lat: lat, lon: lon, genauigkeit: genauigkeit, zeit: zeit)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let dienst = Standort.shared
            dienst.erlaubnis = Standort.erlaubnis(status)
            if status == .authorizedWhenInUse, dienst.an {
                dienst.dienst.requestAlwaysAuthorization()
            }
            dienst.starten()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == "letzter-ort" else { return }
        Task { @MainActor in
            Standort.shared.probeStarten()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
