import SwiftUI

/// Nach der Kopplung (oder in der Demo): Übersicht und Einstellungen.
struct HauptView: View {
    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.scenePhase) private var phase
    @State private var fragtZustimmung = false
    @State private var tab = Reiter.heute
    @StateObject private var lage = Seitenlage()
    /// Nicht beobachtet: Nur die Leiste zeichnet bei jeder Bewegung neu, nicht die ganze Ansicht.
    @State private var stand = Blaetterstand()

    var body: some View {
        // Seiten nebeneinander: Beim Wischen gleitet der Nachbar-Tab mit dem Finger herein.
        // Auf einer Unterseite ist nur das seitliche Blättern gesperrt (dort heißt Wischen vom Rand „zurück“),
        // die Unterseite selbst scrollt ganz normal.
        ZStack(alignment: .bottom) {
            Seiten(tab: $tab,
                   gesperrt: lage.aufUnterseite,
                   platzUnten: lage.aufUnterseite ? 0 : Tableiste.hoehe,
                   seiten: [
                       AnyView(HeuteView().environmentObject(zustand).environmentObject(lage)),
                       AnyView(EssenView().environmentObject(zustand).environmentObject(lage)),
                       AnyView(OrteView().environmentObject(zustand).environmentObject(lage)),
                       AnyView(AuswertungenView().environmentObject(zustand).environmentObject(lage)),
                       AnyView(EinstellungenView().environmentObject(zustand).environmentObject(lage)),
                   ],
                   stand: stand)
                .ignoresSafeArea()
            if !lage.aufUnterseite {
                Tableiste(tab: $tab, stand: stand)
            }
        }
        .ignoresSafeArea(.keyboard)
        .environmentObject(lage)
        // Verlässlichster Zeitpunkt zum Nachsenden: wenn die App geöffnet wird.
        .onChange(of: phase) { _, neu in
            if neu == .active {
                Task {
                    await Warteschlange.shared.senden()
                    await Gesundheit.shared.senden()
                    await Standort.shared.senden(sofort: true)
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
        // Solange Fotos oder Texte geschätzt werden, alle paar Sekunden nachsehen, egal welcher Tab offen ist.
        .task {
            while !Task.isCancelled {
                await Warteschlange.shared.analysenPruefen()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .sheet(isPresented: $fragtZustimmung) {
            ZustimmungView()
        }
    }
}

struct EinstellungenView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @ObservedObject private var gesundheit = Gesundheit.shared
    @ObservedObject private var standort = Standort.shared
    @State private var abmeldenFragen = false
    @State private var abmeldenLaeuft = false
    @AppStorage(Darstellung.schluessel) private var darstellung = Darstellung.system

    var body: some View {
        NavigationStack {
            AppFormular {
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
                        ServerAuskunft()
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
                                    .foregroundStyle(Color.text2)
                            }
                            if let fehler = gesundheit.fehler {
                                Label(fehler, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(Color.warnung)
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
                if !zustand.demo && zustand.verbindung != nil {
                    Section {
                        Toggle("Standort aufzeichnen", isOn: Binding(
                            get: { standort.an },
                            set: { an in
                                if an {
                                    standort.einschalten()
                                } else {
                                    standort.ausschalten()
                                }
                            }))
                        if standort.an {
                            LabeledContent("Erlaubnis", value: erlaubnisText)
                            Toggle("Fahrten selbst erkennen", isOn: $standort.automatisch)
                            if standort.probeSeit != nil {
                                Text("Prüft gerade, ob du losfährst …")
                                    .font(.footnote)
                                    .foregroundStyle(Color.text2)
                            }
                            Toggle("Fahrt aufzeichnen", isOn: Binding(
                                get: { standort.fahrtSeit != nil },
                                set: { an in
                                    if an {
                                        standort.fahrtStarten()
                                    } else {
                                        standort.fahrtBeenden()
                                    }
                                }))
                            if let seit = standort.fahrtSeit {
                                LabeledContent("Fahrt läuft seit", value: seit.formatted(date: .omitted, time: .shortened))
                            }
                            LabeledContent("Noch nicht gesendet", value: standort.wartend == 0 ? "nichts" : "\(standort.wartend) Punkte")
                            if let zuletzt = standort.zuletztGesendet {
                                LabeledContent("Zuletzt gesendet", value: zuletzt.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let fehler = standort.fehler {
                                Label(fehler, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(Color.warnung)
                            }
                        }
                    } header: {
                        Text("Standort")
                    } footer: {
                        Text("Im Alltag meldet iOS größere Ortswechsel und Aufenthalte, das kostet kaum Akku. Mit „Fahrten selbst erkennen“ misst die App nach jedem Aufbruch drei Minuten lang genau; ab etwa 20 km/h wird daraus eine Fahrt, die genau aufgezeichnet wird und nach 5 Minuten Stillstand endet. Fahrrad und Bahn zählen dabei auch. Dafür braucht die App die Erlaubnis „Immer“. Die Punkte gehen an deinen eigenen Server, nie an Claude. Das ersetzt OwnTracks: Schalte es dort aus, sonst läuft beides doppelt.")
                    }
                }
                Section {
                    Picker("Darstellung", selection: $darstellung) {
                        ForEach(Darstellung.allCases) { art in
                            Text(art.name).tag(art)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: darstellung) { _, neu in
                        neu.anwenden()
                    }
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text("„System“ folgt der Einstellung deines iPhones.")
                }
                Section("Entwicklung") {
                    NavigationLink("Probe") { ProbeView().alsUnterseite() }
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

    private var erlaubnisText: String {
        switch standort.erlaubnis {
        case .immer: return "immer"
        case .nurBeimVerwenden: return "nur bei offener App"
        case .abgelehnt: return "abgelehnt"
        case .offen: return "noch nicht gefragt"
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
