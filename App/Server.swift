import CryptoKit
import Foundation
import UIKit

/// Antwort von GET /api/info (nur die Teile, die die Probe braucht).
struct Info: Decodable {
    struct Https: Decodable {
        let port: Int
        let fingerabdruck: String
    }
    let name: String
    let version: String
    let schema: Int?
    let https: Https?
    var claude: Claude? = nil

    struct Claude: Decodable {
        let bereit: Bool
    }
}

struct ProbeAntwort: Decodable {
    let bytes: Int
    let sha256: String
}

enum ProbeFehler: Error {
    case text(String)
}

enum Server {
    static let standardAdresse = ""

    static func url(_ adresse: String, _ pfad: String) throws -> URL {
        var basis = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        while basis.hasSuffix("/") { basis.removeLast() }
        if !basis.contains("://") { basis = "http://" + basis }
        guard let url = URL(string: basis + pfad), url.host != nil else {
            throw ProbeFehler.text("Adresse \"\(adresse)\" ist ungültig.")
        }
        return url
    }

    /// Klartext für die häufigen Fehler, damit die Ursache am iPhone ablesbar ist.
    static func beschreibung(_ fehler: Error) -> String {
        if let probe = fehler as? ProbeFehler, case .text(let text) = probe { return text }
        guard let url = fehler as? URLError else { return fehler.localizedDescription }
        let grund: String
        switch url.code {
        case .appTransportSecurityRequiresSecureConnection:
            grund = "App Transport Security blockiert HTTP"
        case .notConnectedToInternet:
            grund = "kein Netz (oder Hinweis \"Lokales Netzwerk\" abgelehnt)"
        case .timedOut:
            grund = "Zeitüberschreitung: anderes Netz, Server aus oder \"Lokales Netzwerk\" abgelehnt"
        case .cannotConnectToHost:
            grund = "Server antwortet nicht auf diesem Port"
        case .cancelled:
            grund = "abgebrochen (bei HTTPS: Fingerabdruck passt nicht)"
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .secureConnectionFailed:
            grund = "Zertifikat abgelehnt"
        default:
            grund = url.localizedDescription
        }
        return "\(grund) [URLError \(url.code.rawValue)]"
    }

    static func info(_ adresse: String) async throws -> (Info, Double) {
        let start = Date()
        let (daten, antwort) = try await URLSession.shared.data(from: try url(adresse, "/api/info"))
        try pruefen(antwort, daten)
        return (try JSONDecoder().decode(Info.self, from: daten), Date().timeIntervalSince(start))
    }

    /// HTTPS mit dem selbst ausgestellten Zertifikat des Servers: vertraut wird genau dem Fingerabdruck.
    static func infoHttps(host: String, port: Int, fingerabdruck: String) async throws -> (Info, Double) {
        let start = Date()
        let pinning = Pinning(erwartet: fingerabdruck)
        let session = URLSession(configuration: .ephemeral, delegate: pinning, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (daten, antwort) = try await session.data(from: try url("https://\(host):\(port)", "/api/info"))
        try pruefen(antwort, daten)
        return (try JSONDecoder().decode(Info.self, from: daten), Date().timeIntervalSince(start))
    }

    static func hochladen(_ adresse: String, bild: Data) async throws -> (ProbeAntwort, Double) {
        var anfrage = URLRequest(url: try url(adresse, "/api/app/probe"))
        anfrage.httpMethod = "POST"
        anfrage.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let start = Date()
        let (daten, antwort) = try await URLSession.shared.upload(for: anfrage, from: bild)
        try pruefen(antwort, daten)
        return (try JSONDecoder().decode(ProbeAntwort.self, from: daten), Date().timeIntervalSince(start))
    }

    static func pruefen(_ antwort: URLResponse, _ daten: Data) throws {
        guard let http = antwort as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: daten.prefix(200), encoding: .utf8) ?? ""
            throw ProbeFehler.text("HTTP \(http.statusCode): \(text)")
        }
    }

    /// Testbild: farbige Streifen mit Uhrzeit, etwa so groß wie ein echtes Foto.
    static func testbild() -> Data {
        let groesse = CGSize(width: 3000, height: 4000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bild = UIGraphicsImageRenderer(size: groesse, format: format).image { ctx in
            for i in 0..<40 {
                UIColor(hue: CGFloat(i) / 40, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * 100, width: groesse.width, height: 100))
            }
            let text = "Probe \(Date().formatted(date: .numeric, time: .standard))" as NSString
            text.draw(at: CGPoint(x: 100, y: 1800),
                      withAttributes: [.font: UIFont.boldSystemFont(ofSize: 160), .foregroundColor: UIColor.black])
        }
        return bild.jpegData(compressionQuality: 0.9) ?? Data()
    }
}

/// Prüft das Zertifikat des Servers per SHA-256 statt über eine Zertifizierungsstelle.
final class Pinning: NSObject, URLSessionDelegate {
    let erwartet: String

    init(erwartet: String) {
        self.erwartet = erwartet.lowercased().replacingOccurrences(of: ":", with: "")
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let kette = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let blatt = kette.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let der = SecCertificateCopyData(blatt) as Data
        let abdruck = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        if abdruck == erwartet {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
