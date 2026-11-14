import SwiftUI

/// Ein Bestandteil im Formular zum Korrigieren. Zahlen bleiben Text, damit man frei tippen kann.
struct Bestandteilzeile: Identifiable, Equatable {
    let id = UUID()
    var lebensmittel = ""
    var menge = ""
    var einheit = "g"
    var kcal = ""
    var eiweiss = ""
    var kohlenhydrate = ""
    var fett = ""

    static let einheiten = ["g", "ml", "Stück", "Portion"]

    init() {}

    init(_ teil: Bestandteil) {
        lebensmittel = teil.lebensmittel ?? ""
        menge = Self.text(teil.menge)
        einheit = teil.einheit ?? "g"
        kcal = Self.text(teil.kcal)
        eiweiss = Self.text(teil.eiweiss)
        kohlenhydrate = Self.text(teil.kohlenhydrate)
        fett = Self.text(teil.fett)
    }

    static func text(_ wert: Double?) -> String {
        guard let wert else { return "" }
        return Zahl.text((wert * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",")
    }

    /// Zahl aus dem Feld; leer heißt „keine Angabe“. Auch 0 ist erlaubt.
    static func zahl(_ text: String) -> Double? {
        let sauber = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let wert = Double(sauber), wert >= 0, wert.isFinite else { return nil }
        return wert
    }

    /// Neue Menge eintragen und die Nährwerte im selben Verhältnis mitrechnen (halbe Portion, halbe Kalorien).
    mutating func mengeAendern(auf neu: String, umrechnen: Bool) {
        let alt = Self.zahl(menge)
        menge = neu
        guard umrechnen, let alt, alt > 0, let jetzt = Self.zahl(neu) else { return }
        let faktor = jetzt / alt
        kcal = Self.zahl(kcal).map { Self.text($0 * faktor) } ?? kcal
        eiweiss = Self.zahl(eiweiss).map { Self.text($0 * faktor) } ?? eiweiss
        kohlenhydrate = Self.zahl(kohlenhydrate).map { Self.text($0 * faktor) } ?? kohlenhydrate
        fett = Self.zahl(fett).map { Self.text($0 * faktor) } ?? fett
    }

    var json: [String: Any] {
        var inhalt: [String: Any] = ["lebensmittel": lebensmittel.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let wert = Self.zahl(menge) {
            inhalt["menge"] = wert
            inhalt["einheit"] = einheit
        }
        for (feld, text) in [("kcal", kcal), ("eiweiss_g", eiweiss), ("kohlenhydrate_g", kohlenhydrate), ("fett_g", fett)] {
            if let wert = Self.zahl(text) { inhalt[feld] = wert }
        }
        return inhalt
    }
}

/// Korrektur einer Mahlzeit für `PUT /api/essen/{id}`: Alle Bestandteile werden ersetzt.
struct Mahlzeitkorrektur: Equatable {
    var zeilen: [Bestandteilzeile]
    var notiz: String

    init(_ mahlzeit: Mahlzeit) {
        zeilen = (mahlzeit.bestandteile ?? []).map { Bestandteilzeile($0) }
        notiz = mahlzeit.notiz ?? ""
    }

    /// Grobe Prüfung vor dem Senden. `nil` heißt: in Ordnung.
    var fehler: String? {
        if zeilen.isEmpty { return "Eine Mahlzeit braucht mindestens einen Bestandteil. Zum Entfernen die Mahlzeit löschen." }
        for (stelle, zeile) in zeilen.enumerated() {
            if zeile.lebensmittel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Bestandteil \(stelle + 1) hat keinen Namen."
            }
            for text in [zeile.menge, zeile.kcal, zeile.eiweiss, zeile.kohlenhydrate, zeile.fett] {
                if !text.trimmingCharacters(in: .whitespaces).isEmpty && Bestandteilzeile.zahl(text) == nil {
                    return "Bestandteil \(stelle + 1): „\(text)“ ist keine Zahl."
                }
            }
        }
        return nil
    }

    func koerper() throws -> Data {
        let inhalt: [String: Any] = ["bestandteile": zeilen.map(\.json),
                                     "notiz": notiz.trimmingCharacters(in: .whitespacesAndNewlines)]
        return try JSONSerialization.data(withJSONObject: inhalt, options: [.sortedKeys])
    }

    var kcal: Double? {
        let werte = zeilen.compactMap { Bestandteilzeile.zahl($0.kcal) }
        return werte.isEmpty ? nil : werte.reduce(0, +)
    }
}

/// Einzelheiten einer Mahlzeit, wie auf der Essen-Seite des Dashboards, mit Ändern und Löschen.
struct MahlzeitView: View {
    let mahlzeit: Mahlzeit
    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.dismiss) private var schliessen
    @State private var art: String?
    @State private var bilder: [Int: UIImage] = [:]
    @State private var fehler: String?
    @State private var bearbeitet = false
    @State private var loeschenFragen = false
    @State private var laeuft = false

    var body: some View {
        List {
            if let fehler {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                }
            }
            if !(mahlzeit.fotos ?? []).isEmpty {
                Section {
                    ForEach(mahlzeit.fotos ?? [], id: \.self) { auftrag in
                        if let bild = bilder[auftrag] {
                            Image(uiImage: bild)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("Foto der Mahlzeit")
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                }
            }
            Section {
                ForEach(Array((mahlzeit.bestandteile ?? []).enumerated()), id: \.offset) { _, teil in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(teil.lebensmittel ?? "ohne Namen")
                            Spacer()
                            Text(Zahl.kcal(teil.kcal))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.secondary)
                        }
                        Text(untertitel(teil))
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
            } header: {
                Text("Bestandteile")
            }
            Section {
                LabeledContent("Kalorien", value: (mahlzeit.geschaetzt ? "≈ " : "") + Zahl.kcal(mahlzeit.summe?.kcal))
                LabeledContent("Eiweiß", value: Zahl.gramm(mahlzeit.summe?.eiweiss))
                LabeledContent("Kohlenhydrate", value: Zahl.gramm(mahlzeit.summe?.kohlenhydrate))
                LabeledContent("Fett", value: Zahl.gramm(mahlzeit.summe?.fett))
            } header: {
                Text("Zusammen")
            } footer: {
                if mahlzeit.geschaetzt {
                    Text("Geschätzte Werte können um 20 bis 30 % abweichen.")
                }
            }
            Section {
                LabeledContent("Herkunft", value: mahlzeit.herkunft)
                if let sicherheit = mahlzeit.daten?.sicherheit, mahlzeit.korrigiert != true {
                    LabeledContent("Sicherheit der Schätzung", value: sicherheit)
                }
                if let gewogen = mahlzeit.daten?.gewogen {
                    LabeledContent("Gewogen", value: Zahl.gramm(gewogen))
                }
                if let hinweis = mahlzeit.daten?.hinweis, !hinweis.isEmpty {
                    Text(hinweis)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                if let notiz = mahlzeit.notiz, !notiz.isEmpty {
                    LabeledContent("Notiz", value: notiz)
                }
            } header: {
                Text("Einschätzung")
            }
            if mahlzeit.aenderbar != false {
                Section {
                    Picker("Art", selection: Binding(get: { art ?? mahlzeit.art ?? "" }, set: { artSetzen($0) })) {
                        ForEach(Mahlzeit.arten, id: \.self) { Text($0) }
                    }
                    .disabled(laeuft)
                } footer: {
                    if mahlzeit.artGeschaetzt == true && art == nil {
                        Text("Die Art ist aus der Uhrzeit geschätzt.")
                    }
                }
                Section {
                    Button("Bestandteile ändern") { bearbeitet = true }
                    Button("Mahlzeit löschen", role: .destructive) { loeschenFragen = true }
                } footer: {
                    Text("Ändern und Löschen geht nur, wenn dein Server erreichbar ist.")
                }
                .disabled(laeuft)
            } else {
                Section {
                    Text("Diese Mahlzeit kommt aus Apple Health und lässt sich hier nicht ändern.")
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .navigationTitle(mahlzeit.uhrzeit.map { "\(mahlzeit.art ?? "Mahlzeit"), \($0)" } ?? "Mahlzeit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await bilderLaden() }
        .sheet(isPresented: $bearbeitet) {
            MahlzeitBearbeiten(mahlzeit: mahlzeit) { schliessen() }
        }
        .confirmationDialog("Diese Mahlzeit löschen?", isPresented: $loeschenFragen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { await loeschen() }
            }
        }
    }

    private func untertitel(_ teil: Bestandteil) -> String {
        var teile: [String] = []
        if !teil.mengeText.isEmpty { teile.append(teil.mengeText) }
        if teil.eiweiss != nil || teil.kohlenhydrate != nil || teil.fett != nil {
            teile.append("E \(Zahl.gramm(teil.eiweiss)) · K \(Zahl.gramm(teil.kohlenhydrate)) · F \(Zahl.gramm(teil.fett))")
        }
        return teile.joined(separator: " · ")
    }

    private func bilderLaden() async {
        guard let api = try? zustand.api() else { return }
        for auftrag in mahlzeit.fotos ?? [] where bilder[auftrag] == nil {
            if let daten = try? await api.daten("GET", "/api/essen/foto/\(auftrag)/bild"), let bild = UIImage(data: daten) {
                bilder[auftrag] = bild
            }
        }
    }

    private func artSetzen(_ neu: String) {
        guard !neu.isEmpty, neu != (art ?? mahlzeit.art) else { return }
        laeuft = true
        Task {
            defer { laeuft = false }
            do {
                let koerper = try JSONSerialization.data(withJSONObject: ["art": neu])
                _ = try await zustand.api().schicken("PUT", "/api/essen/\(mahlzeit.id)/art", koerper: koerper)
                art = neu
                fehler = nil
                Warteschlange.shared.geaendert()
            } catch {
                fehler = Api.text(error)
            }
        }
    }

    private func loeschen() async {
        laeuft = true
        defer { laeuft = false }
        do {
            _ = try await zustand.api().daten("DELETE", "/api/essen/\(mahlzeit.id)")
            Warteschlange.shared.geaendert()
            schliessen()
        } catch {
            fehler = Api.text(error)
        }
    }
}

/// Bestandteile einer Mahlzeit von Hand korrigieren.
struct MahlzeitBearbeiten: View {
    let mahlzeit: Mahlzeit
    let fertig: () -> Void
    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.dismiss) private var schliessen
    @State private var korrektur: Mahlzeitkorrektur
    @State private var umrechnen = true
    @State private var fehler: String?
    @State private var speichert = false

    init(mahlzeit: Mahlzeit, fertig: @escaping () -> Void) {
        self.mahlzeit = mahlzeit
        self.fertig = fertig
        _korrektur = State(initialValue: Mahlzeitkorrektur(mahlzeit))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.orange)
                    }
                }
                Section {
                    Toggle("Nährwerte mit der Menge umrechnen", isOn: $umrechnen)
                } footer: {
                    Text("Eingeschaltet ändern sich Kalorien und Nährwerte im selben Verhältnis, wenn du die Menge änderst. So korrigierst du am schnellsten eine falsch geschätzte Portion.")
                }
                ForEach($korrektur.zeilen) { $zeile in
                    Section {
                        TextField("Lebensmittel", text: $zeile.lebensmittel)
                        HStack {
                            TextField("Menge", text: Binding(
                                get: { zeile.menge },
                                set: { zeile.mengeAendern(auf: $0, umrechnen: umrechnen) }))
                                .keyboardType(.decimalPad)
                            Picker("Einheit", selection: $zeile.einheit) {
                                ForEach(Bestandteilzeile.einheiten, id: \.self) { Text($0) }
                            }
                            .labelsHidden()
                        }
                        feld("Kalorien", $zeile.kcal)
                        feld("Eiweiß in g", $zeile.eiweiss)
                        feld("Kohlenhydrate in g", $zeile.kohlenhydrate)
                        feld("Fett in g", $zeile.fett)
                        Button("Bestandteil entfernen", role: .destructive) {
                            korrektur.zeilen.removeAll { $0.id == zeile.id }
                        }
                    }
                }
                Section {
                    Button("Bestandteil hinzufügen") { korrektur.zeilen.append(Bestandteilzeile()) }
                    TextField("Notiz", text: $korrektur.notiz)
                } footer: {
                    Text("Zusammen \(Zahl.kcal(korrektur.kcal)). Nach dem Speichern gilt die Mahlzeit als von Hand korrigiert; die ursprüngliche Schätzung merkt sich der Server.")
                }
            }
            .navigationTitle("Mahlzeit ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(speichert ? "Speichert …" : "Speichern") {
                        Task { await speichern() }
                    }
                    .disabled(speichert)
                }
            }
        }
    }

    private func feld(_ name: String, _ text: Binding<String>) -> some View {
        LabeledContent(name) {
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func speichern() async {
        if let grund = korrektur.fehler {
            fehler = grund
            return
        }
        speichert = true
        defer { speichert = false }
        do {
            _ = try await zustand.api().schicken("PUT", "/api/essen/\(mahlzeit.id)", koerper: try korrektur.koerper())
            Warteschlange.shared.geaendert()
            schliessen()
            fertig()
        } catch {
            fehler = Api.text(error)
        }
    }
}
