import SwiftUI
import UIKit

/// Der einzige Bildschirm der Probe: Adresse, vier Prüfungen, Protokoll.
struct ProbeView: View {
    @AppStorage("adresse") private var adresse = Server.standardAdresse
    @ObservedObject private var protokoll = Protokoll.shared
    @State private var info: Info?
    @State private var laeuft = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://192.168.0.10:8000", text: $adresse)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let info {
                        LabeledContent("Name", value: info.name)
                        LabeledContent("Version", value: info.version)
                        LabeledContent("HTTPS", value: info.https.map { "Port \($0.port)" } ?? "aus")
                    }
                }
                Section("Prüfen") {
                    Button("1. Server erreichen (HTTP)") { ausfuehren(serverPruefen) }
                    Button("2. HTTPS mit Fingerabdruck") { ausfuehren(httpsPruefen) }
                        .disabled(info?.https == nil)
                    Button("3. Testbild senden") { ausfuehren(hochladen) }
                    Button("4. Testbild im Hintergrund senden") { ausfuehren(hintergrund) }
                }
                .disabled(laeuft)
                Section {
                    if protokoll.eintraege.isEmpty {
                        Text("Noch nichts geprüft.").foregroundStyle(.secondary)
                    }
                    ForEach(protokoll.eintraege) { eintrag in
                        HStack(alignment: .top) {
                            Image(systemName: eintrag.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(eintrag.ok ? .green : .red)
                            VStack(alignment: .leading) {
                                Text(eintrag.text).font(.callout)
                                Text(eintrag.zeit.formatted(date: .omitted, time: .standard))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Protokoll")
                        Spacer()
                        Button("Kopieren") { UIPasteboard.general.string = protokoll.alsText }
                        Button("Leeren", role: .destructive) { protokoll.leeren() }
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Probe")
            .overlay { if laeuft { ProgressView() } }
        }
    }

    private func ausfuehren(_ schritt: @escaping () async -> Void) {
        laeuft = true
        Task {
            await schritt()
            laeuft = false
        }
    }

    private func serverPruefen() async {
        do {
            let (antwort, dauer) = try await Server.info(adresse)
            info = antwort
            protokoll.neu("HTTP: \(antwort.name) \(antwort.version) in \(ms(dauer))", ok: true)
        } catch {
            protokoll.neu("HTTP: \(Server.beschreibung(error))", ok: false)
        }
    }

    private func httpsPruefen() async {
        guard let https = info?.https, let host = try? Server.url(adresse, "/").host else { return }
        do {
            let (antwort, dauer) = try await Server.infoHttps(host: host, port: https.port,
                                                              fingerabdruck: https.fingerabdruck)
            protokoll.neu("HTTPS: \(antwort.name) in \(ms(dauer)), Fingerabdruck passt", ok: true)
        } catch {
            protokoll.neu("HTTPS: \(Server.beschreibung(error))", ok: false)
        }
    }

    private func hochladen() async {
        let bild = Server.testbild()
        do {
            let (antwort, dauer) = try await Server.hochladen(adresse, bild: bild)
            let gleich = antwort.bytes == bild.count
            protokoll.neu("Upload: \(antwort.bytes / 1024) KB in \(ms(dauer))\(gleich ? "" : ", Größe weicht ab!")",
                          ok: gleich)
        } catch {
            protokoll.neu("Upload: \(Server.beschreibung(error))", ok: false)
        }
    }

    private func hintergrund() async {
        do {
            try Hintergrund.shared.starten(adresse: adresse, bild: Server.testbild(), warten: 30)
            protokoll.neu("Hintergrund-Upload gestartet, der Server antwortet erst nach 30 s. Jetzt die App verlassen "
                          + "oder wegwischen, das Ergebnis erscheint hier.", ok: true)
        } catch {
            protokoll.neu("Hintergrund-Upload: \(Server.beschreibung(error))", ok: false)
        }
    }

    private func ms(_ sekunden: Double) -> String {
        "\(Int(sekunden * 1000)) ms"
    }
}
