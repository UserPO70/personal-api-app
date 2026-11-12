import SwiftUI

/// Nach der Kopplung (oder in der Demo): Übersicht und Einstellungen.
struct HauptView: View {
    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.scenePhase) private var phase
    @State private var fragtZustimmung = false

    var body: some View {
        TabView {
            UebersichtView()
                .tabItem { Label("Heute", systemImage: "sun.max") }
            EssenView()
                .tabItem { Label("Essen", systemImage: "fork.knife") }
            EinstellungenView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        // Verlässlichster Zeitpunkt zum Nachsenden: wenn die App geöffnet wird.
        .onChange(of: phase) { _, neu in
            if neu == .active {
                Task {
                    await Warteschlange.shared.senden()
                    await Gesundheit.shared.senden()
                }
            }
        }
        .onAppear {
            if zustand.zustimmung == .offen { fragtZustimmung = true }
            Warteschlange.shared.netzBeobachten()
        }
        // Solange die App offen ist: regelmäßig nachsehen, ob der Server inzwischen erreichbar ist.
        // Die Wartezeit je Eintrag gilt dabei weiter, es wird also nicht alle 20 Sekunden gesendet.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await Warteschlange.shared.senden()
            }
        }
        .sheet(isPresented: $fragtZustimmung) {
            ZustimmungView()
        }
    }
}

private struct Wartend: Decodable {
    struct App: Decodable, Identifiable {
        let id: String
        let name: String?
        let pruefzahl: String?
    }
    let wartend: [App]
}

/// Vorläufig: zeigt, ob die Verbindung steht. Die Tagesübersicht folgt in einem späteren Schritt.
struct UebersichtView: View {
    @EnvironmentObject private var zustand: AppZustand
    @State private var info: Info?
    @State private var fehler: String?
    @State private var laedt = false

    var body: some View {
        NavigationStack {
            List {
                if zustand.demo {
                    Section {
                        Label("Demo: ausgedachte Daten, kein Server", systemImage: "theatermasks")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Server") {
                    if let info {
                        zeile("Name", info.name)
                        zeile("Version", info.version)
                        zeile("Verbindung", verschluesselt ? "verschlüsselt" : "unverschlüsselt")
                        zeile("Fotoanalyse", info.claude?.bereit == true ? "bereit" : "nicht bereit")
                    } else if let fehler {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        ProgressView()
                    }
                }
                Section {
                    Text("Hier erscheint bald dein Tag: Essen, Schritte, Wege und PC-Zeit.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Heute")
            .refreshable { await laden() }
            .task { await laden() }
        }
    }

    private var verschluesselt: Bool {
        zustand.demo ? true : zustand.verbindung?.verschluesselt == true
    }

    private func zeile(_ name: String, _ wert: String) -> some View {
        LabeledContent(name, value: wert)
    }

    private func laden() async {
        if zustand.demo {
            info = Info(name: "mein-server", version: "0.1.0", schema: nil, https: nil, claude: Info.Claude(bereit: true))
            return
        }
        guard !laedt else { return }
        laedt = true
        defer { laedt = false }
        do {
            let api = try zustand.api()
            let neu = try await api.lesen(Info.self, "GET", "/api/info")
            // Prüft zugleich, ob der Schlüssel noch gilt.
            _ = try await api.lesen(Wartend.self, "GET", "/api/app/wartend")
            info = neu
            fehler = nil
        } catch {
            if (error as? URLError)?.code == .cancelled, Task.isCancelled { return }
            info = nil
            fehler = Api.text(error)
        }
    }
}

struct EinstellungenView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @ObservedObject private var gesundheit = Gesundheit.shared
    @State private var abmeldenFragen = false
    @State private var abmeldenLaeuft = false

    var body: some View {
        NavigationStack {
            Form {
                if zustand.demo {
                    Section {
                        Button("Demo beenden") { zustand.demo = false }
                    } footer: {
                        Text("Danach kannst du deinen eigenen Server einrichten.")
                    }
                } else if let verbindung = zustand.verbindung {
                    Section("Server") {
                        LabeledContent("Adresse", value: verbindung.adresse)
                        LabeledContent("Verbindung", value: verbindung.verschluesselt ? "verschlüsselt" : "unverschlüsselt")
                        LabeledContent("Dieses Gerät", value: verbindung.geraetName)
                    }
                    Section {
                        Button("Vom Server abmelden", role: .destructive) { abmeldenFragen = true }
                            .disabled(abmeldenLaeuft)
                    } footer: {
                        Text("Der Server vergisst diese App. Deine Daten auf dem Server bleiben erhalten.")
                    }
                }
                Section {
                    Toggle("Fotoanalyse mit Claude", isOn: Binding(
                        get: { zustand.zustimmung == .ja },
                        set: { zustand.zustimmung = $0 ? .ja : .nein }))
                    LabeledContent("Warteschlange", value: schlange.eintraege.isEmpty ? "leer" : "\(schlange.eintraege.count) offen")
                } header: {
                    Text("Essen")
                } footer: {
                    Text("Eingeschaltet schickt dein Server Fotos und Texte zur Schätzung der Nährwerte an Claude von Anthropic, über dein eigenes Claude-Konto. Ausgeschaltet bleiben Barcode und Favoriten.")
                }
                if Gesundheit.verfuegbar && !zustand.demo && zustand.verbindung != nil {
                    Section {
                        Toggle("Apple Health senden", isOn: Binding(
                            get: { gesundheit.an },
                            set: { an in
                                if an {
                                    Task { await gesundheit.einschalten() }
                                } else {
                                    gesundheit.ausschalten()
                                }
                            }))
                        if gesundheit.an {
                            if let zuletzt = gesundheit.zuletzt {
                                LabeledContent("Zuletzt gesendet", value: zuletzt.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let stand = gesundheit.stand {
                                Text(stand)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                            if let fehler = gesundheit.fehler {
                                Label(fehler, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(Color.orange)
                            }
                            Button(gesundheit.laeuft ? "Sendet …" : "Jetzt senden") {
                                Task { await gesundheit.senden() }
                            }
                            .disabled(gesundheit.laeuft)
                        }
                    } header: {
                        Text("Gesundheit")
                    } footer: {
                        Text("Schritte, Strecke, Stockwerke, Gehtempo, Schrittlänge und Schlaf gehen an deinen eigenen Server, nie an Claude. Das ersetzt den Health-Kurzbefehl: Schalte dessen Automation aus, sonst können Stunden doppelt zählen.")
                    }
                }
                Section("Entwicklung") {
                    NavigationLink("Probe") { ProbeView() }
                }
                Section {
                    LabeledContent("App-Version", value: version)
                }
            }
            .navigationTitle("Einstellungen")
            .confirmationDialog("Diese App vom Server abmelden?", isPresented: $abmeldenFragen, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { abmelden() }
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let kurz = info?["CFBundleShortVersionString"] as? String ?? "?"
        let bau = info?["CFBundleVersion"] as? String ?? "?"
        return "\(kurz) (\(bau))"
    }

    /// Meldet sich am Server ab, wenn er erreichbar ist, und vergisst die Verbindung in jedem Fall.
    private func abmelden() {
        guard let verbindung = zustand.verbindung else { return }
        abmeldenLaeuft = true
        Task {
            if let api = try? zustand.api() {
                _ = try? await api.daten("DELETE", "/api/geraete/\(verbindung.geraetId)")
            }
            zustand.vergessen()
            abmeldenLaeuft = false
        }
    }
}
