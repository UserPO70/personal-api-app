import AppIntents
import Foundation

/// Für die Probe, ob eine Kurzbefehl-Automation (etwa bei Ankunft zuhause) das Senden auslöst.
struct TestbildSenden: AppIntent {
    static var title: LocalizedStringResource = "Testbild senden"
    static var description = IntentDescription("Schickt ein Testbild im Hintergrund an den Server (Probe).")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let adresse = UserDefaults.standard.string(forKey: "adresse") ?? Server.standardAdresse
        try Hintergrund.shared.starten(adresse: adresse, bild: Server.testbild())
        await Protokoll.shared.neu("Kurzbefehl: Hintergrund-Upload gestartet", ok: true)
        return .result(dialog: "Testbild wird gesendet.")
    }
}

/// Für eine Automation „Mit WLAN verbunden“: schickt nach, was unterwegs erfasst wurde.
struct WarteschlangeSenden: AppIntent {
    static var title: LocalizedStringResource = "Warteschlange senden"
    static var description = IntentDescription("Schickt unterwegs erfasstes Essen an deinen Server.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let schlange = Warteschlange.shared
        let vorher = schlange.eintraege.count
        await schlange.senden(alle: true)
        let offen = schlange.eintraege.count
        if vorher == 0 { return .result(dialog: "Die Warteschlange ist leer.") }
        if offen == 0 { return .result(dialog: "\(vorher) gesendet.") }
        return .result(dialog: "\(vorher - offen) gesendet, \(offen) noch offen.")
    }
}

/// Für eine Automation „Bluetooth: mit dem Auto verbunden“.
struct FahrtAufzeichnen: AppIntent {
    static var title: LocalizedStringResource = "Fahrt aufzeichnen"
    static var description = IntentDescription("Zeichnet den Standort genau auf, bis die Fahrt endet.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let standort = Standort.shared
        guard standort.an else {
            return .result(dialog: "Die Standortaufzeichnung ist in der App ausgeschaltet.")
        }
        standort.fahrtStarten()
        return .result(dialog: "Die Fahrt wird aufgezeichnet.")
    }
}

/// Für eine Automation „Bluetooth: vom Auto getrennt“.
struct FahrtBeenden: AppIntent {
    static var title: LocalizedStringResource = "Fahrt beenden"
    static var description = IntentDescription("Beendet die genaue Aufzeichnung und schickt die Punkte an deinen Server.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Standort.shared.fahrtBeenden()
        return .result(dialog: "Die Fahrt ist beendet.")
    }
}

struct Kurzbefehle: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FahrtAufzeichnen(),
                    phrases: ["Fahrt mit \(.applicationName) aufzeichnen"],
                    shortTitle: "Fahrt aufzeichnen",
                    systemImageName: "car")
        AppShortcut(intent: FahrtBeenden(),
                    phrases: ["Fahrt mit \(.applicationName) beenden"],
                    shortTitle: "Fahrt beenden",
                    systemImageName: "car.fill")
        AppShortcut(intent: WarteschlangeSenden(),
                    phrases: ["Warteschlange mit \(.applicationName) senden"],
                    shortTitle: "Warteschlange senden",
                    systemImageName: "tray.and.arrow.up")
        AppShortcut(intent: TestbildSenden(),
                    phrases: ["Testbild mit \(.applicationName) senden"],
                    shortTitle: "Testbild senden",
                    systemImageName: "photo")
    }
}
