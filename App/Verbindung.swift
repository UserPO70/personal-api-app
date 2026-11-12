import Foundation
import Security

/// Der gekoppelte Server. Der Schlüssel liegt getrennt im Schlüsselbund.
struct Verbindung: Codable, Equatable {
    var adresse: String
    var fingerabdruck: String?
    var geraetId: String
    var geraetName: String

    var verschluesselt: Bool { adresse.lowercased().hasPrefix("https://") }
}

/// Schlüssel der App im Schlüsselbund von iOS (nicht in den Einstellungen, nicht im Backup anderer Geräte).
enum Schluesselbund {
    private static let dienst = "io.github.userpo70.personalapi"
    private static let konto = "app-schluessel"

    private static var suche: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: dienst,
         kSecAttrAccount as String: konto]
    }

    static func speichern(_ schluessel: String) {
        loeschen()
        var eintrag = suche
        eintrag[kSecValueData as String] = Data(schluessel.utf8)
        // Auch bei gesperrtem iPhone lesbar, damit später Uploads im Hintergrund gehen.
        eintrag[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(eintrag as CFDictionary, nil)
    }

    static func lesen() -> String? {
        var anfrage = suche
        anfrage[kSecReturnData as String] = true
        anfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: AnyObject?
        guard SecItemCopyMatching(anfrage as CFDictionary, &ergebnis) == errSecSuccess,
              let daten = ergebnis as? Data else { return nil }
        return String(data: daten, encoding: .utf8)
    }

    static func loeschen() {
        SecItemDelete(suche as CFDictionary)
    }
}

/// Was die ganze App wissen muss: gekoppelt, Demo oder noch nichts.
@MainActor
final class AppZustand: ObservableObject {
    private static let ablage = "verbindung"

    @Published private(set) var verbindung: Verbindung?
    @Published var demo = false
    /// Einladung aus einem QR-Code, der mit der Kamera-App gescannt wurde (personal-api://koppeln?...).
    @Published var einladung: Einladung?

    init() {
        if let daten = UserDefaults.standard.data(forKey: Self.ablage),
           let alt = try? JSONDecoder().decode(Verbindung.self, from: daten),
           Schluesselbund.lesen() != nil {
            verbindung = alt
        }
    }

    func gekoppelt(_ neu: Verbindung, schluessel: String) {
        Schluesselbund.speichern(schluessel)
        if let daten = try? JSONEncoder().encode(neu) {
            UserDefaults.standard.set(daten, forKey: Self.ablage)
        }
        UserDefaults.standard.set(neu.adresse, forKey: "adresse")  // für Probe und Kurzbefehl
        demo = false
        verbindung = neu
    }

    func vergessen() {
        Schluesselbund.loeschen()
        UserDefaults.standard.removeObject(forKey: Self.ablage)
        verbindung = nil
    }

    func api() throws -> Api {
        guard let verbindung else { throw ApiFehler.ungueltig("Kein Server gekoppelt.") }
        return try Api(adresse: verbindung.adresse, fingerabdruck: verbindung.fingerabdruck,
                       schluessel: Schluesselbund.lesen())
    }
}
