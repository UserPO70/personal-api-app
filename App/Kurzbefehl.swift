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

struct Kurzbefehle: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TestbildSenden(),
                    phrases: ["Testbild mit \(.applicationName) senden"],
                    shortTitle: "Testbild senden",
                    systemImageName: "photo")
    }
}
