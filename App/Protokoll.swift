import Foundation

/// Ergebnisse der Probe, damit sie auch nach einem Neustart der App noch ablesbar sind.
struct Protokollzeile: Codable, Identifiable, Hashable {
    var id = UUID()
    var zeit = Date()
    var text: String
    var ok: Bool
}

@MainActor
final class Protokoll: ObservableObject {
    static let shared = Protokoll()
    private static let schluessel = "protokoll"

    @Published private(set) var eintraege: [Protokollzeile] = []

    init() {
        if let daten = UserDefaults.standard.data(forKey: Self.schluessel),
           let alt = try? JSONDecoder().decode([Protokollzeile].self, from: daten) {
            eintraege = alt
        }
    }

    func neu(_ text: String, ok: Bool) {
        eintraege.insert(Protokollzeile(text: text, ok: ok), at: 0)
        if eintraege.count > 100 { eintraege.removeLast(eintraege.count - 100) }
        if let daten = try? JSONEncoder().encode(eintraege) {
            UserDefaults.standard.set(daten, forKey: Self.schluessel)
        }
    }

    func leeren() {
        eintraege = []
        UserDefaults.standard.removeObject(forKey: Self.schluessel)
    }

    /// Alles als Text zum Kopieren und Weitergeben.
    var alsText: String {
        let format = DateFormatter()
        format.dateFormat = "dd.MM. HH:mm:ss"
        return eintraege.map { "\(format.string(from: $0.zeit)) \($0.ok ? "OK" : "FEHLER") \($0.text)" }
            .joined(separator: "\n")
    }
}
