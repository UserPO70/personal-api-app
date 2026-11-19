import SwiftUI

/// Orte benennen und „Kein Halt“ am Server. Dieselben Adressen wie die Seite „Meine Orte“ im Dashboard.
enum Ortsdienst {
    /// Ein Ort in der Liste des Servers mit demselben Namen wie der Aufenthalt (Namen wie „Ort 12“ sind eindeutig).
    static func ort(zu name: String, in orte: [BekannterOrt]) -> BekannterOrt? {
        orte.first { $0.name == name }
    }

    /// „Zuhause“ legt die Einrichtung des Servers fest, nicht ein eigener Name.
    static func istZuhause(_ name: String, ort: BekannterOrt?) -> Bool {
        (ort?.automatischerName ?? name) == "Zuhause" && ort?.nameId == nil
    }

    static func json(_ inhalt: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: inhalt, options: [.sortedKeys])
    }

    static func benennen(_ api: Api, name: String, ort: BekannterOrt?, lat: Double, lon: Double) async throws {
        if let nameId = ort?.nameId {
            _ = try await api.schicken("PUT", "/api/orte/namen/\(nameId)", koerper: try json(["name": name]))
        } else {
            _ = try await api.schicken("POST", "/api/orte/namen",
                                       koerper: try json(["name": name, "lat": ort?.lat ?? lat, "lon": ort?.lon ?? lon]))
        }
    }

    static func ausblenden(_ api: Api, lat: Double, lon: Double, bestaetigt: Bool) async throws {
        _ = try await api.schicken("POST", "/api/orte/ausgeblendet",
                                   koerper: try json(["lat": lat, "lon": lon, "bestaetigt": bestaetigt]))
    }
}

/// Antippen eines Orts im Ablauf: benennen, eigenen Namen entfernen oder „Kein Halt“.
struct OrtBlatt: View {
    let aufenthalt: Ortstag.Aufenthalt
    let tag: String
    let ort: BekannterOrt?
    /// Nach einer Änderung: Tag neu laden.
    let geaendert: () async -> Void

    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.dismiss) private var schliessen
    @State private var name = ""
    @State private var fehler: String?
    @State private var arbeitet = false
    @State private var fragtKeinHalt = false
    @State private var fragtTrotzName = false
    @FocusState private var tippt: Bool

    private var zuhause: Bool { Ortsdienst.istZuhause(aufenthalt.ort, ort: ort) }
    private var lat: Double { ort?.lat ?? aufenthalt.lat ?? 0 }
    private var lon: Double { ort?.lon ?? aufenthalt.lon ?? 0 }

    var body: some View {
        NavigationStack {
            AppFormular {
                Section {
                    LabeledContent("Hier", value: Zeitpunkt.spanne(aufenthalt.beginn, aufenthalt.ende, tag: tag))
                    if let automatisch = ort?.automatischerName, automatisch != aufenthalt.ort {
                        LabeledContent("Ohne eigenen Namen", value: automatisch)
                    }
                }
                if zuhause {
                    Section {
                        Text("„Zuhause“ kommt aus der Einrichtung des Servers und lässt sich hier nicht umbenennen.")
                            .foregroundStyle(Color.text2)
                    }
                } else {
                    Section {
                        TextField("z. B. Arbeit, Bäcker, Oma", text: $name)
                            .focused($tippt)
                            .submitLabel(.done)
                            .onSubmit { Task { await benennen() } }
                    } header: {
                        Text(ort?.nameId == nil ? "Name" : "Eigener Name")
                    } footer: {
                        Text("Gilt für diesen Ort, auch an anderen Tagen und für künftige Besuche.")
                    }
                    if ort?.nameId != nil {
                        Section {
                            Button("Eigenen Namen entfernen", role: .destructive) { Task { await nameEntfernen() } }
                        }
                    }
                    Section {
                        Button("Kein Halt", role: .destructive) { fragtKeinHalt = true }
                    } footer: {
                        Text("Für Stellen, an denen du nicht wirklich warst: Ampel, Stau oder eine Lücke im GPS. Der Ort "
                             + "und seine Aufenthalte zählen dann nicht mehr, auch künftig an dieser Stelle nicht, und die "
                             + "Fahrt davor und danach wird eine. Gelöscht wird nichts; rückgängig unter „Meine Orte“.")
                    }
                }
                if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.warnung)
                    }
                }
            }
            .disabled(arbeitet)
            .navigationTitle(aufenthalt.ort)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                if !zuhause {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { Task { await benennen() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || arbeitet)
                    }
                }
            }
            .confirmationDialog("„\(aufenthalt.ort)“ ist kein echter Halt?", isPresented: $fragtKeinHalt,
                                titleVisibility: .visible) {
                Button("Kein Halt", role: .destructive) { Task { await keinHalt(bestaetigt: false) } }
            } message: {
                Text("Der Ort wird ausgeblendet, auch für künftige Besuche an dieser Stelle.")
            }
            .confirmationDialog("„\(aufenthalt.ort)“ trägt einen Namen.", isPresented: $fragtTrotzName,
                                titleVisibility: .visible) {
                Button("Trotzdem ausblenden", role: .destructive) { Task { await keinHalt(bestaetigt: true) } }
            } message: {
                Text("Der Name bleibt gespeichert und gilt wieder, wenn du den Ort unter „Meine Orte“ wieder anzeigst.")
            }
            .onAppear {
                if ort?.nameId != nil { name = aufenthalt.ort }
            }
        }
    }

    private func ausfuehren(_ arbeit: (Api) async throws -> Void) async -> Bool {
        arbeitet = true
        defer { arbeitet = false }
        do {
            try await arbeit(try zustand.api())
            fehler = nil
            await geaendert()
            schliessen()
            return true
        } catch {
            fehler = Api.text(error)
            return false
        }
    }

    private func benennen() async {
        let neu = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !neu.isEmpty else { return }
        guard neu.count <= 60 else {
            fehler = "Höchstens 60 Zeichen."
            return
        }
        _ = await ausfuehren { api in
            try await Ortsdienst.benennen(api, name: neu, ort: ort, lat: lat, lon: lon)
        }
    }

    private func nameEntfernen() async {
        guard let nameId = ort?.nameId else { return }
        _ = await ausfuehren { api in _ = try await api.daten("DELETE", "/api/orte/namen/\(nameId)") }
    }

    private func keinHalt(bestaetigt: Bool) async {
        arbeitet = true
        defer { arbeitet = false }
        do {
            try await Ortsdienst.ausblenden(try zustand.api(), lat: lat, lon: lon, bestaetigt: bestaetigt)
            fehler = nil
            await geaendert()
            schliessen()
        } catch ApiFehler.status(409, _) {
            fragtTrotzName = true
        } catch {
            fehler = Api.text(error)
        }
    }
}

/// Alle eigenen Namen und ausgeblendeten Stellen: umbenennen, löschen, wieder anzeigen.
struct MeineOrteView: View {
    @EnvironmentObject private var zustand: AppZustand
    @State private var namen: [Ortsname] = []
    @State private var ausgeblendet: [AusgeblendeterOrt] = []
    @State private var geladen = false
    @State private var fehler: String?
    @State private var umbenennen: Ortsname?
    @State private var neuerName = ""

    var body: some View {
        AppListe {
            if let fehler {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warnung)
                }
            }
            Section {
                if geladen && namen.isEmpty {
                    Text("Noch keine eigenen Namen. Tippe im Tab „Orte“ auf einen Ort, um ihn zu benennen.")
                        .foregroundStyle(Color.text2)
                }
                ForEach(namen) { eintrag in
                    Button {
                        neuerName = eintrag.name
                        umbenennen = eintrag
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eintrag.name)
                                .foregroundStyle(Color.text)
                            if eintrag.orte == 0 {
                                Text("Derzeit kein Ort in der Nähe")
                                    .font(.footnote)
                                    .foregroundStyle(Color.text3)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Löschen", role: .destructive) {
                            Task { await ausfuehren("DELETE", "/api/orte/namen/\(eintrag.id)") }
                        }
                    }
                }
            } header: {
                Text("Eigene Namen")
            } footer: {
                if !namen.isEmpty { Text("Antippen zum Umbenennen, nach links wischen zum Löschen.") }
            }
            Section {
                if geladen && ausgeblendet.isEmpty {
                    Text("Nichts ausgeblendet.")
                        .foregroundStyle(Color.text2)
                }
                ForEach(ausgeblendet) { stelle in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stelle.bezeichnung)
                        if let wann = stelle.erstelltAm.flatMap(Zeitpunkt.lesen) {
                            Text("seit \(wann.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote)
                                .foregroundStyle(Color.text3)
                        }
                    }
                    .swipeActions {
                        Button("Wieder anzeigen") {
                            Task { await ausfuehren("DELETE", "/api/orte/ausgeblendet/\(stelle.id)") }
                        }
                        .tint(Color.orte)
                    }
                }
            } header: {
                Text("Kein Halt")
            } footer: {
                if !ausgeblendet.isEmpty { Text("Nach links wischen, um eine Stelle wieder als Ort zu zählen.") }
            }
        }
        .navigationTitle("Meine Orte")
        .refreshable { await laden() }
        .task { await laden() }
        .alert("Umbenennen", isPresented: Binding(get: { umbenennen != nil }, set: { if !$0 { umbenennen = nil } })) {
            TextField("Name", text: $neuerName)
            Button("Abbrechen", role: .cancel) { umbenennen = nil }
            Button("Speichern") {
                guard let eintrag = umbenennen else { return }
                let name = neuerName.trimmingCharacters(in: .whitespacesAndNewlines)
                umbenennen = nil
                guard !name.isEmpty else { return }
                Task {
                    await ausfuehren { api in
                        _ = try await api.schicken("PUT", "/api/orte/namen/\(eintrag.id)",
                                                   koerper: try Ortsdienst.json(["name": name]))
                    }
                }
            }
        }
    }

    private func laden() async {
        if zustand.demo {
            namen = [Ortsname(id: 1, name: "Arbeit", lat: 0, lon: 0, orte: 1)]
            ausgeblendet = []
            geladen = true
            return
        }
        do {
            let api = try zustand.api()
            namen = try await api.lesen([Ortsname].self, "GET", "/api/orte/namen")
            ausgeblendet = try await api.lesen([AusgeblendeterOrt].self, "GET", "/api/orte/ausgeblendet")
            fehler = nil
        } catch {
            if Task.isCancelled { return }
            fehler = Api.text(error)
        }
        geladen = true
    }

    private func ausfuehren(_ methode: String, _ pfad: String) async {
        await ausfuehren { api in _ = try await api.daten(methode, pfad) }
    }

    private func ausfuehren(_ arbeit: (Api) async throws -> Void) async {
        guard !zustand.demo else { return }
        do {
            try await arbeit(try zustand.api())
            await laden()
        } catch {
            fehler = Api.text(error)
        }
    }
}
