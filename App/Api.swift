import Foundation

enum ApiFehler: Error {
    case status(Int, String)
    case ungueltig(String)
}

/// Anfragen an den gekoppelten Server. Bei HTTPS vertraut die App genau dem Fingerabdruck aus dem QR-Code
/// und sendet sonst nichts, auch nicht den Schlüssel.
final class Api {
    let adresse: String
    private let schluessel: String?
    private let session: URLSession

    init(adresse: String, fingerabdruck: String?, schluessel: String?) throws {
        let konfiguration = URLSessionConfiguration.ephemeral
        konfiguration.timeoutIntervalForRequest = 15
        if adresse.lowercased().hasPrefix("https://") {
            guard let fingerabdruck, fingerabdruck.count == 64 else {
                throw ApiFehler.ungueltig("Für HTTPS fehlt der Fingerabdruck des Servers. Bitte den QR-Code scannen.")
            }
            session = URLSession(configuration: konfiguration, delegate: Pinning(erwartet: fingerabdruck),
                                 delegateQueue: nil)
        } else {
            session = URLSession(configuration: konfiguration)
        }
        self.adresse = adresse
        self.schluessel = schluessel
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// `mit` ersetzt den gespeicherten Schlüssel (beim Koppeln gibt es noch keinen gespeicherten).
    func daten(_ methode: String, _ pfad: String, json: [String: String]? = nil, mit eigener: String? = nil) async throws -> Data {
        var anfrage = URLRequest(url: try Server.url(adresse, pfad))
        anfrage.httpMethod = methode
        if let bearer = eigener ?? schluessel {
            anfrage.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
            anfrage.httpBody = try JSONEncoder().encode(json)
        }
        let (daten, antwort) = try await session.data(for: anfrage)
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ApiFehler.status(status, Self.detail(daten))
        }
        return daten
    }

    /// Für die Warteschlange: gibt auch Fehlerantworten zurück, damit sie nach dem Status entscheiden kann.
    func senden(_ anfrage: Anfrage) async throws -> (Int, Data) {
        var auftrag = URLRequest(url: try Server.url(adresse, anfrage.pfad))
        auftrag.httpMethod = "POST"
        auftrag.timeoutInterval = 60
        if let schluessel {
            auftrag.setValue("Bearer \(schluessel)", forHTTPHeaderField: "Authorization")
        }
        auftrag.setValue(anfrage.typ, forHTTPHeaderField: "Content-Type")
        let (daten, antwort) = try await session.upload(for: auftrag, from: anfrage.koerper)
        return ((antwort as? HTTPURLResponse)?.statusCode ?? 0, daten)
    }

    static func fehlertext(_ daten: Data) -> String {
        detail(daten)
    }

    func lesen<T: Decodable>(_ typ: T.Type, _ methode: String, _ pfad: String, json: [String: String]? = nil,
                             mit eigener: String? = nil) async throws -> T {
        try JSONDecoder().decode(typ, from: try await daten(methode, pfad, json: json, mit: eigener))
    }

    private struct Detail: Decodable {
        let detail: String
    }

    private static func detail(_ daten: Data) -> String {
        if let detail = try? JSONDecoder().decode(Detail.self, from: daten) { return detail.detail }
        return String(data: daten.prefix(200), encoding: .utf8) ?? ""
    }

    /// Fehlertext für Menschen.
    static func text(_ fehler: Error) -> String {
        guard let api = fehler as? ApiFehler else { return Server.beschreibung(fehler) }
        switch api {
        case .ungueltig(let text):
            return text
        case .status(401, _):
            return "Der Server kennt diese App nicht (mehr). Bitte neu koppeln."
        case .status(let status, let detail):
            return detail.isEmpty ? "Der Server antwortet mit Fehler \(status)." : "\(detail) [\(status)]"
        }
    }
}
