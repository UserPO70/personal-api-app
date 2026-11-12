import CryptoKit
import Foundation
import UIKit

/// Inhalt des QR-Codes: personal-api://koppeln?v=1&adresse=...&code=...&fingerabdruck=...
struct Einladung: Equatable, Identifiable {
    let adresse: String
    let code: String
    let fingerabdruck: String?

    var id: String { adresse + "|" + code }
    var verschluesselt: Bool { adresse.lowercased().hasPrefix("https://") }

    /// Aus dem Text eines QR-Codes. `nil`, wenn es kein Kopplungs-Code dieser App ist.
    init?(text: String) {
        guard let teile = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              teile.scheme?.lowercased() == "personal-api", teile.host?.lowercased() == "koppeln" else { return nil }
        var werte: [String: String] = [:]
        for eintrag in teile.queryItems ?? [] { werte[eintrag.name] = eintrag.value ?? "" }
        if let version = werte["v"], version != "1" { return nil }
        guard let adresse = werte["adresse"], let code = werte["code"] else { return nil }
        let abdruck = werte["fingerabdruck"]?.lowercased()
        self.init(adresse: adresse, code: code, fingerabdruck: (abdruck ?? "").isEmpty ? nil : abdruck)
    }

    /// Von Hand eingegeben oder aus dem QR-Code. HTTPS geht nur mit Fingerabdruck.
    init?(adresse: String, code: String, fingerabdruck: String? = nil) {
        var adresse = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        while adresse.hasSuffix("/") { adresse.removeLast() }
        if !adresse.contains("://") { adresse = "http://" + adresse }
        let code = code.filter { $0.isNumber }
        guard let url = URL(string: adresse), url.host != nil, let schema = url.scheme?.lowercased(),
              schema == "http" || schema == "https", !code.isEmpty else { return nil }
        if schema == "https" {
            guard let fingerabdruck, fingerabdruck.count == 64,
                  fingerabdruck.allSatisfy({ $0.isHexDigit }) else { return nil }
        }
        self.adresse = adresse
        self.code = code
        self.fingerabdruck = fingerabdruck
    }
}

/// Rechnen für die Kopplung, getrennt vom Netz, damit es sich testen lässt.
enum Pruefzahl {
    static func hex(_ daten: some Sequence<UInt8>) -> String {
        daten.map { String(format: "%02x", $0) }.joined()
    }

    /// 64 Hex-Zeichen Zufall.
    static func zufall() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let ergebnis = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(ergebnis == errSecSuccess, "Kein Zufall verfügbar")
        return hex(bytes)
    }

    /// Die Zusage legt die App auf ihren Zufall fest, ohne ihn zu verraten.
    static func zusage(_ appZufall: String) -> String {
        hex(SHA256.hash(data: Data(appZufall.utf8)))
    }

    /// SHA-256 von "personal-api-pruefzahl|<app>|<server>", erste 8 Byte als Zahl, modulo 1 000 000.
    static func berechnen(appZufall: String, serverZufall: String) -> String {
        let summe = SHA256.hash(data: Data("personal-api-pruefzahl|\(appZufall)|\(serverZufall)".utf8))
        var zahl: UInt64 = 0
        for byte in summe.prefix(8) { zahl = zahl << 8 | UInt64(byte) }
        return String(format: "%06llu", zahl % 1_000_000)
    }
}

private struct KoppelAntwort: Decodable {
    let status: String
    let geraet_id: String
    let name: String?
    let schluessel: String
    let server_zufall: String?
}

private struct PruefzahlAntwort: Decodable {
    let pruefzahl: String
}

private struct StatusAntwort: Decodable {
    let status: String
}

/// Ablauf der Kopplung: Code einlösen, Prüfzahl zeigen, auf die Bestätigung am Server warten.
@MainActor
final class Kopplung: ObservableObject {
    enum Stand: Equatable {
        case verbinden
        case wartet(pruefzahl: String)
        case fertig
        case fehler(String)
    }

    @Published private(set) var stand: Stand = .verbinden

    func ausfuehren(_ einladung: Einladung, zustand: AppZustand) async {
        stand = .verbinden
        do {
            let api = try Api(adresse: einladung.adresse, fingerabdruck: einladung.fingerabdruck, schluessel: nil)
            let appZufall = Pruefzahl.zufall()
            let antwort = try await api.lesen(KoppelAntwort.self, "POST", "/api/app/koppeln", json: [
                "code": einladung.code, "name": UIDevice.current.name, "app_zusage": Pruefzahl.zusage(appZufall)])
            let verbindung = Verbindung(adresse: einladung.adresse, fingerabdruck: einladung.fingerabdruck,
                                        geraetId: antwort.geraet_id, geraetName: antwort.name ?? UIDevice.current.name)
            if antwort.status != "frei" {
                guard let serverZufall = antwort.server_zufall else {
                    throw ApiFehler.ungueltig("Der Server hat keine Zufallszahl geschickt. Ist er aktuell?")
                }
                let vomServer = try await api.lesen(PruefzahlAntwort.self, "POST", "/api/app/koppeln/pruefzahl",
                                                    json: ["app_zufall": appZufall], mit: antwort.schluessel)
                let eigene = Pruefzahl.berechnen(appZufall: appZufall, serverZufall: serverZufall)
                guard eigene == vomServer.pruefzahl else {
                    throw ApiFehler.ungueltig("Die Prüfzahl von App und Server stimmt nicht überein. Kopplung abgebrochen.")
                }
                stand = .wartet(pruefzahl: eigene)
                try await aufBestaetigungWarten(api, schluessel: antwort.schluessel)
            }
            zustand.gekoppelt(verbindung, schluessel: antwort.schluessel)
            stand = .fertig
        } catch is CancellationError {
            // Bildschirm geschlossen
        } catch let fehler as ApiFehler {
            if case .status(401, _) = fehler {
                stand = .fehler("Der Code ist falsch, abgelaufen oder schon benutzt. Bitte am Server einen neuen erzeugen.")
            } else {
                stand = .fehler(Api.text(fehler))
            }
        } catch {
            if (error as? URLError)?.code == .cancelled, Task.isCancelled { return }
            stand = .fehler(Api.text(error))
        }
    }

    /// Fragt alle 2 Sekunden nach, höchstens 10 Minuten (so lange gilt die Kopplung am Server).
    private func aufBestaetigungWarten(_ api: Api, schluessel: String) async throws {
        for _ in 0..<300 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                let antwort = try await api.lesen(StatusAntwort.self, "GET", "/api/app/koppeln/status", mit: schluessel)
                if antwort.status == "frei" { return }
            } catch ApiFehler.status(401, _) {
                throw ApiFehler.ungueltig("Die Kopplung wurde am Server abgelehnt oder ist abgelaufen.")
            } catch let fehler as URLError where fehler.code != .cancelled {
                continue  // kurz kein Netz: weiter versuchen
            }
        }
        throw ApiFehler.ungueltig("Niemand hat die Kopplung am Server bestätigt. Bitte noch einmal versuchen.")
    }
}
