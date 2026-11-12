import Foundation

/// Upload über eine Hintergrund-Session: läuft weiter, wenn die App in den Hintergrund geht oder beendet wird.
final class Hintergrund: NSObject, URLSessionDataDelegate {
    static let shared = Hintergrund()
    static let kennung = "io.github.userpo70.personalapi.upload"

    var abschluss: (() -> Void)?
    private var antworten: [Int: Data] = [:]
    private let sperre = NSLock()

    lazy var session: URLSession = {
        let konfiguration = URLSessionConfiguration.background(withIdentifier: Self.kennung)
        konfiguration.isDiscretionary = false
        konfiguration.sessionSendsLaunchEvents = true
        return URLSession(configuration: konfiguration, delegate: self, delegateQueue: nil)
    }()

    /// Hintergrund-Uploads gehen nur aus einer Datei.
    func starten(adresse: String, bild: Data) throws {
        let datei = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString).jpg")
        try bild.write(to: datei)
        var anfrage = URLRequest(url: try Server.url(adresse, "/api/app/probe"))
        anfrage.httpMethod = "POST"
        anfrage.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let aufgabe = session.uploadTask(with: anfrage, fromFile: datei)
        aufgabe.taskDescription = String(Date().timeIntervalSince1970)
        aufgabe.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        sperre.lock()
        antworten[dataTask.taskIdentifier, default: Data()].append(data)
        sperre.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        sperre.lock()
        let daten = antworten.removeValue(forKey: task.taskIdentifier) ?? Data()
        sperre.unlock()
        let start = Double(task.taskDescription ?? "") ?? Date().timeIntervalSince1970
        let dauer = Date().timeIntervalSince1970 - start
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let text: String
        let ok: Bool
        if let error {
            text = "Hintergrund-Upload: \(Server.beschreibung(error))"
            ok = false
        } else if (200..<300).contains(status), let probe = try? JSONDecoder().decode(ProbeAntwort.self, from: daten) {
            text = "Hintergrund-Upload: \(probe.bytes / 1024) KB angekommen nach \(String(format: "%.0f", dauer)) s"
            ok = true
        } else {
            text = "Hintergrund-Upload: HTTP \(status) \(String(data: daten.prefix(200), encoding: .utf8) ?? "")"
            ok = false
        }
        Task { @MainActor in Protokoll.shared.neu(text, ok: ok) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.abschluss?()
            self.abschluss = nil
        }
    }
}
