import Foundation
import HealthKit

/// Eine Messung für `POST /api/health`: Zahl oder (beim Schlaf) Name der Phase, mit Beginn und Ende.
struct Probe {
    let wert: Any
    let start: Date
    let ende: Date
}

/// Baut die Sendung an den Server. Ohne HealthKit, damit es sich testen lässt.
enum Gesundheitspaket {
    /// Ohne Daten vom Server reicht die erste Sendung so viele Tage zurück.
    static let tageZurueck = 30
    /// Bei jeder weiteren Sendung gehen die letzten Stunden noch einmal mit: Health trägt Werte nach,
    /// und der Server überschreibt dieselbe Stunde, statt sie doppelt zu zählen.
    static let nachlauf: TimeInterval = 48 * 3600

    static func zeit(_ datum: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: datum)
    }

    /// Liest die Zeiten des Servers („2026-03-14T20:55:14.545226Z“).
    static func zeitLesen(_ text: String?) -> Date? {
        guard let text, text.count >= 19 else { return nil }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: String(text.prefix(19)) + "Z")
    }

    static func volleStunde(_ datum: Date) -> Date {
        Date(timeIntervalSince1970: (datum.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    /// Ab wann die App liefert. Hat der Server schon Health-Daten (vom Kurzbefehl), geht es mit der Stunde
    /// des letzten Eintrags weiter, damit ältere Stunden nicht ein zweites Mal gezählt werden.
    static func startgrenze(letzter: Date?, jetzt: Date) -> Date {
        let frueh = volleStunde(jetzt.addingTimeInterval(-Double(tageZurueck) * 86400))
        guard let letzter, letzter > frueh else { return frueh }
        return volleStunde(min(letzter, jetzt))
    }

    static func beginn(startgrenze: Date, ersteFertig: Bool, jetzt: Date) -> Date {
        guard ersteFertig else { return startgrenze }
        return max(startgrenze, volleStunde(jetzt.addingTimeInterval(-nachlauf)))
    }

    static func block(_ proben: [Probe], einheit: String?) -> [String: Any] {
        var block: [String: Any] = [
            "werte": proben.map(\.wert),
            "start": proben.map { zeit($0.start) },
            "ende": proben.map { zeit($0.ende) },
        ]
        if let einheit { block["einheit"] = einheit }
        return block
    }

    static func koerper(_ bloecke: [String: [String: Any]]) throws -> Data {
        var inhalt: [String: Any] = bloecke
        inhalt["geraet"] = Eintrag.geraet
        return try JSONSerialization.data(withJSONObject: inhalt, options: [.sortedKeys])
    }

    /// Namen der Schlafphasen, wie der Server sie kennt (Zahlen aus HealthKit).
    static func schlafphase(_ wert: Int) -> String {
        switch wert {
        case 0: return "Im Bett"
        case 2: return "Wach"
        case 3: return "Kern"
        case 4: return "Tief"
        case 5: return "REM"
        default: return "Schlafend"
        }
    }
}

/// GET /api/quellen
struct Quellenzeile: Decodable {
    let quelle: String
    let typ: String?
    let letzter: String?
}

/// Antwort auf POST /api/health
struct Gesundheitsantwort: Decodable {
    let messwerte: Int?
    let uebersprungen: Int?
}

/// Liest Schritte, Strecke, Stockwerke, Gehtempo, Schrittlänge und Schlaf aus Apple Health und schickt sie
/// an den eigenen Server. Ersetzt den Health-Kurzbefehl. Diese Daten gehen nie an Claude.
@MainActor
final class Gesundheit: ObservableObject {
    static let shared = Gesundheit()

    static var verfuegbar: Bool { HKHealthStore.isHealthDataAvailable() }

    private enum Ablage {
        static let an = "health-an"
        static let startgrenze = "health-startgrenze"
        static let ersteFertig = "health-erste-fertig"
        static let zuletzt = "health-zuletzt"
    }

    private struct Summe {
        let feld: String
        let kennung: HKQuantityTypeIdentifier
        let einheit: HKUnit
        let name: String?
    }

    /// Je Stunde zusammengezählt, wie der Kurzbefehl es tat.
    private static let summen = [
        Summe(feld: "schritte", kennung: .stepCount, einheit: .count(), name: nil),
        Summe(feld: "strecke", kennung: .distanceWalkingRunning, einheit: .meter(), name: "m"),
        Summe(feld: "stockwerke", kennung: .flightsClimbed, einheit: .count(), name: nil),
    ]

    /// Einzelne Messungen: Der Server bildet daraus das Tagesmittel.
    private static let einzeln = [
        Summe(feld: "gehtempo", kennung: .walkingSpeed, einheit: HKUnit.meter().unitDivided(by: .second()), name: "m/s"),
        Summe(feld: "schrittlaenge", kennung: .walkingStepLength, einheit: .meterUnit(with: .centi), name: "cm"),
    ]

    private static var typen: Set<HKObjectType> {
        var typen: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]
        for eintrag in summen + einzeln {
            typen.insert(HKQuantityType(eintrag.kennung))
        }
        return typen
    }

    @Published private(set) var an = UserDefaults.standard.bool(forKey: Ablage.an)
    @Published private(set) var laeuft = false
    @Published private(set) var stand: String?
    @Published private(set) var fehler: String?
    @Published private(set) var zuletzt: Date?

    private let speicher = HKHealthStore()
    private var beobachter: [HKObserverQuery] = []

    init() {
        let wann = UserDefaults.standard.double(forKey: Ablage.zuletzt)
        if wann > 0 { zuletzt = Date(timeIntervalSince1970: wann) }
    }

    // MARK: Ein und aus

    /// Fragt iOS nach der Erlaubnis und beginnt zu senden.
    func einschalten() async {
        guard Self.verfuegbar else {
            fehler = "Auf diesem Gerät gibt es Apple Health nicht."
            return
        }
        do {
            try await speicher.requestAuthorization(toShare: [], read: Self.typen)
        } catch {
            fehler = "Die Erlaubnis für Apple Health ließ sich nicht abfragen: \(error.localizedDescription)"
            return
        }
        an = true
        UserDefaults.standard.set(true, forKey: Ablage.an)
        beobachten()
        await senden()
    }

    func ausschalten() {
        an = false
        UserDefaults.standard.set(false, forKey: Ablage.an)
        for abfrage in beobachter { speicher.stop(abfrage) }
        beobachter = []
        speicher.disableAllBackgroundDelivery { _, _ in }
        stand = nil
        fehler = nil
    }

    /// Beim Start der App: iOS weckt die App nur, wenn die Beobachter dann schon wieder angemeldet sind.
    func starten() {
        guard an, Self.verfuegbar else { return }
        beobachten()
    }

    private func beobachten() {
        guard beobachter.isEmpty else { return }
        for typ in Self.typen {
            guard let probentyp = typ as? HKSampleType else { continue }
            let abfrage = HKObserverQuery(sampleType: probentyp, predicate: nil) { _, fertig, _ in
                Task { @MainActor in
                    await Gesundheit.shared.senden()
                    fertig()
                }
            }
            speicher.execute(abfrage)
            beobachter.append(abfrage)
            speicher.enableBackgroundDelivery(for: typ, frequency: .hourly) { _, _ in }
        }
    }

    // MARK: Senden

    func senden() async {
        guard an, !laeuft, let api = AppZustand.gespeicherteApi() else { return }
        laeuft = true
        defer { laeuft = false }
        let jetzt = Date()
        do {
            let grenze = try await startgrenze(api, jetzt: jetzt)
            let ersteFertig = UserDefaults.standard.bool(forKey: Ablage.ersteFertig)
            let von = Gesundheitspaket.beginn(startgrenze: grenze, ersteFertig: ersteFertig, jetzt: jetzt)
            var bloecke: [String: [String: Any]] = [:]
            var anzahl = 0
            for summe in Self.summen {
                let proben = try await stundensummen(summe, von: von, bis: jetzt)
                if !proben.isEmpty { bloecke[summe.feld] = Gesundheitspaket.block(proben, einheit: summe.name) }
                anzahl += proben.count
            }
            for messung in Self.einzeln {
                let proben = try await messungen(messung, von: von, bis: jetzt)
                if !proben.isEmpty { bloecke[messung.feld] = Gesundheitspaket.block(proben, einheit: messung.name) }
                anzahl += proben.count
            }
            let schlaf = try await schlafproben(von: von, bis: jetzt)
            if !schlaf.isEmpty { bloecke["schlaf"] = Gesundheitspaket.block(schlaf, einheit: nil) }
            anzahl += schlaf.count

            guard anzahl > 0 else {
                stand = "Health hat seit \(von.formatted(date: .abbreviated, time: .shortened)) keine Werte geliefert. Prüfe in der Health-App unter Teilen, ob diese App lesen darf."
                fehler = nil
                return
            }
            let anfrage = Anfrage(pfad: "/api/health", typ: "application/json",
                                  koerper: try Gesundheitspaket.koerper(bloecke))
            let (status, daten) = try await api.senden(anfrage)
            guard (200..<300).contains(status) else {
                throw ApiFehler.status(status, Api.fehlertext(daten))
            }
            let antwort = try? JSONDecoder().decode(Gesundheitsantwort.self, from: daten)
            UserDefaults.standard.set(true, forKey: Ablage.ersteFertig)
            UserDefaults.standard.set(jetzt.timeIntervalSince1970, forKey: Ablage.zuletzt)
            zuletzt = jetzt
            let uebersprungen = antwort?.uebersprungen ?? 0
            stand = "\(antwort?.messwerte ?? anzahl) Messwerte gesendet" + (uebersprungen > 0 ? ", \(uebersprungen) vom Server übersprungen" : "")
            fehler = nil
        } catch {
            fehler = Api.text(error)
        }
    }

    /// Einmal festgelegt und dann gemerkt, damit die App nie hinter den Wechsel vom Kurzbefehl zurückgreift.
    private func startgrenze(_ api: Api, jetzt: Date) async throws -> Date {
        let gemerkt = UserDefaults.standard.double(forKey: Ablage.startgrenze)
        if gemerkt > 0 { return Date(timeIntervalSince1970: gemerkt) }
        let quellen = try await api.lesen([Quellenzeile].self, "GET", "/api/quellen")
        let stuendlich = Set(Self.summen.map(\.feld))
        let letzter = quellen
            .filter { $0.quelle == "health" && stuendlich.contains($0.typ ?? "") }
            .compactMap { Gesundheitspaket.zeitLesen($0.letzter) }
            .max()
        let grenze = Gesundheitspaket.startgrenze(letzter: letzter, jetzt: jetzt)
        UserDefaults.standard.set(grenze.timeIntervalSince1970, forKey: Ablage.startgrenze)
        return grenze
    }

    // MARK: Aus Health lesen

    private func stundensummen(_ summe: Summe, von: Date, bis: Date) async throws -> [Probe] {
        let zeitraum = HKQuery.predicateForSamples(withStart: von, end: bis)
        let abfrage = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(summe.kennung), predicate: zeitraum),
            options: .cumulativeSum,
            anchorDate: von,
            intervalComponents: DateComponents(hour: 1))
        let sammlung = try await abfrage.result(for: speicher)
        var proben: [Probe] = []
        sammlung.enumerateStatistics(from: von, to: bis) { statistik, _ in
            if let wert = statistik.sumQuantity()?.doubleValue(for: summe.einheit), wert > 0 {
                proben.append(Probe(wert: (wert * 1000).rounded() / 1000, start: statistik.startDate, ende: statistik.endDate))
            }
        }
        return proben
    }

    private func messungen(_ messung: Summe, von: Date, bis: Date) async throws -> [Probe] {
        let zeitraum = HKQuery.predicateForSamples(withStart: von, end: bis)
        let abfrage = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(messung.kennung), predicate: zeitraum)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await abfrage.result(for: speicher).map { probe in
            Probe(wert: probe.quantity.doubleValue(for: messung.einheit), start: probe.startDate, ende: probe.endDate)
        }
    }

    private func schlafproben(von: Date, bis: Date) async throws -> [Probe] {
        let zeitraum = HKQuery.predicateForSamples(withStart: von, end: bis)
        let abfrage = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: zeitraum)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await abfrage.result(for: speicher).map { probe in
            Probe(wert: Gesundheitspaket.schlafphase(probe.value), start: probe.startDate, ende: probe.endDate)
        }
    }
}
