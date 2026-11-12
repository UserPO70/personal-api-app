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

struct Kurzbefehle: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
