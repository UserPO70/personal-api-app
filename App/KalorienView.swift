import Charts
import SwiftUI

/// Kalorienrechner: Angaben zur Person, Richtwert mit Rechenweg und der Verlauf gegen das Ziel.
/// Ein Richtwert aus einer Formel, keine medizinische Beratung. Die Angaben gehen nie an Claude.
struct KalorienView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var stand: Kalorienstand?
    @State private var verlauf: Kalorienverlauf?
    @State private var eingabe = Kalorieneingabe()
    @State private var geladen = false
    @State private var speichert = false
    @State private var fehler: String?
    @State private var loeschenFragen = false
    @State private var zeigtRechenweg = false

    var body: some View {
        Form {
            if let fehler {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                }
            }
            if !geladen {
                Section { ProgressView() }
            } else {
                richtwert
                angaben
                if let verlauf, stand?.angaben != nil {
                    diagramm(verlauf)
                    gegenprobe(verlauf)
                }
                if stand?.angaben != nil {
                    Section {
                        Button("Angaben löschen", role: .destructive) { loeschenFragen = true }
                    } footer: {
                        Text("Entfernt deine Angaben und alle Ziele vom Server. Essen und Gewicht bleiben.")
                    }
                }
            }
        }
        .navigationTitle("Kalorienrechner")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await laden() }
        .task { await laden() }
        .onChange(of: schlange.neuesAmServer) {
            Task { await laden(nurAnzeige: true) }
        }
        .confirmationDialog("Angaben und Ziele löschen?", isPresented: $loeschenFragen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { await loeschen() }
            }
        }
    }

    // MARK: Richtwert

    private var richtwert: some View {
        Section {
            if let ziel = stand?.ziel {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Zahl.kcal(ziel.kcal)) am Tag")
                        .font(.title2.bold())
                    Text(ziel.quelle == "eigenes" ? "dein eigenes Ziel" : "gerechneter Richtwert")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                if let rechnung = stand?.rechnung {
                    if let grundumsatz = rechnung.grundumsatz {
                        LabeledContent("Grundumsatz", value: Zahl.kcal(grundumsatz))
                    }
                    if let bedarf = rechnung.bedarf {
                        LabeledContent("Bedarf", value: Zahl.kcal(bedarf))
                    }
                    if ziel.quelle == "eigenes", let gerechnet = rechnung.zielGerechnet {
                        LabeledContent("Gerechnetes Ziel", value: Zahl.kcal(gerechnet))
                    }
                    if !rechnung.rechenweg.isEmpty {
                        DisclosureGroup("So wird gerechnet", isExpanded: $zeigtRechenweg) {
                            ForEach(rechnung.rechenweg, id: \.self) { schritt in
                                Text(schritt)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    ForEach(rechnung.grenzen, id: \.self) { grenze in
                        Label(grenze, systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
                if let abweichung = stand?.abweichung, abs(abweichung) >= 25, let neu = stand?.rechnung?.ziel {
                    Label("Mit deinem aktuellen Gewicht ergibt die Rechnung \(Zahl.kcal(neu)). Speichern übernimmt den neuen Stand.",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                }
            } else {
                Text(ohneZiel)
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            Text("Dein Richtwert")
        } footer: {
            Text("Richtwert aus einer Formel, keine medizinische Beratung. Der einzelne Bedarf kann spürbar abweichen.")
        }
    }

    private var ohneZiel: String {
        if stand?.angaben == nil {
            return "Trag unten deine Angaben ein. Daraus und aus deinem Gewicht entsteht ein Richtwert für die Kalorien am Tag."
        }
        return stand?.rechnung?.grund ?? stand?.grund ?? "Noch kein Ziel."
    }

    // MARK: Angaben

    private var angaben: some View {
        Section {
            LabeledContent("Größe in cm") {
                TextField("z. B. 178", text: $eingabe.groesse)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Geburtsjahr") {
                TextField("z. B. 1990", text: $eingabe.geburtsjahr)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Geschlecht (für die Formel)", selection: $eingabe.geschlecht) {
                Text("männlich").tag("m")
                Text("weiblich").tag("w")
            }
            Picker("Aktivität", selection: $eingabe.aktivitaet) {
                ForEach(stufen) { stufe in
                    Text(stufe.name).tag(stufe.stufe)
                }
            }
            if let beschreibung = stufen.first(where: { $0.stufe == eingabe.aktivitaet })?.beschreibung {
                Text(beschreibung)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            Picker("Ziel", selection: $eingabe.ziel) {
                ForEach(["halten", "abnehmen", "zunehmen"], id: \.self) { ziel in
                    Text(Kalorientext.ziel(ziel)).tag(ziel)
                }
            }
            if eingabe.ziel != "halten" {
                Picker("Tempo", selection: $eingabe.tempo) {
                    ForEach(Kalorieneingabe.tempi, id: \.self) { tempo in
                        Text(Kalorientext.tempo(tempo)).tag(tempo)
                    }
                }
            }
            LabeledContent("Eigenes Ziel in kcal") {
                TextField("freiwillig", text: $eingabe.eigenesZiel)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Button(speichert ? "Speichert …" : "Speichern") {
                Task { await speichern() }
            }
            .disabled(speichert)
        } header: {
            Text("Angaben")
        } footer: {
            Text("Höchstens 1 kg je Woche, und das Ziel fällt nie unter den Grundumsatz. Ein eigenes Ziel geht der Rechnung vor. Das Ziel gilt ab dem Tag des Speicherns, frühere Tage behalten ihres. Die Angaben bleiben auf deinem Server und gehen nie an Claude.")
        }
    }

    private var stufen: [Kalorienstand.Stufe] {
        stand?.stufen ?? []
    }

    // MARK: Verlauf

    private func diagramm(_ verlauf: Kalorienverlauf) -> some View {
        Section {
            if verlauf.tage.contains(where: { $0.kcal != nil }) {
                Chart {
                    ForEach(verlauf.tage) { tag in
                        if let datum = Gewichtsverlauf.datum(tag.tag), let kcal = tag.kcal {
                            BarMark(x: .value("Tag", datum, unit: .day), y: .value("kcal", kcal))
                                .foregroundStyle(by: .value("Reihe", "Gegessen"))
                                .cornerRadius(3)
                        }
                    }
                    ForEach(verlauf.tage) { tag in
                        if let datum = Gewichtsverlauf.datum(tag.tag), let ziel = tag.ziel {
                            LineMark(x: .value("Tag", datum, unit: .day), y: .value("kcal", ziel))
                                .foregroundStyle(by: .value("Reihe", "Ziel"))
                                .interpolationMethod(.stepCenter)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
                .chartForegroundStyleScale(["Gegessen": Color.essen.opacity(0.55), "Ziel": Color.primary])
                .chartYScale(domain: verlauf.achse)
                .chartYAxisLabel("kcal")
                .frame(height: 220)
                .padding(.vertical, 4)
                .accessibilityLabel("Gegessene Kalorien je Tag und das Ziel, letzte 30 Tage")
            } else {
                Text("In den letzten 30 Tagen ist kein Essen erfasst.")
                    .foregroundStyle(Color.secondary)
            }
            if let mittel = verlauf.wochenmittel?.kcal {
                LabeledContent("Mittel der letzten 7 Tage", value: Zahl.kcal(mittel))
            }
        } header: {
            Text("Letzte 30 Tage")
        } footer: {
            Text("Tage ohne erfasstes Essen bleiben leer und zählen nicht als 0. Werte aus Fotos sind Schätzungen.")
        }
    }

    private func gegenprobe(_ verlauf: Kalorienverlauf) -> some View {
        Section {
            if let probe = verlauf.gegenprobe {
                if let geschaetzt = probe.bedarfGeschaetzt {
                    LabeledContent("Bedarf aus Gewicht und Essen", value: Zahl.kcal(geschaetzt))
                    if let gerechnet = probe.bedarfGerechnet {
                        LabeledContent("Bedarf laut Formel", value: Zahl.kcal(gerechnet))
                    }
                    if let hinweis = probe.hinweis {
                        Label(hinweis, systemImage: "info.circle")
                            .font(.footnote)
                    }
                } else {
                    Text(probe.grund ?? "Dafür reichen die Daten noch nicht.")
                        .foregroundStyle(Color.secondary)
                }
            }
        } header: {
            Text("Gegenprobe")
        } footer: {
            Text("Aus deinem Gewichtsverlauf und dem Gegessenen der letzten 4 Wochen zurückgerechnet. Weicht das deutlich von der Formel ab, passt die Aktivitätsstufe nicht, oder es wurde nicht alles erfasst.")
        }
    }

    // MARK: Server

    /// `nurAnzeige`: das Formular nicht überschreiben, während jemand tippt.
    private func laden(nurAnzeige: Bool = false) async {
        do {
            let api = try zustand.api()
            let neu = try await api.lesen(Kalorienstand.self, "GET", "/api/kalorien/profil")
            stand = neu
            if !nurAnzeige, let angaben = neu.angaben { eingabe = Kalorieneingabe(angaben) }
            verlauf = try? await api.lesen(Kalorienverlauf.self, "GET", "/api/kalorien/verlauf?tage=30")
            schlange.merken(neu, als: "kalorien")
            fehler = nil
        } catch {
            if Task.isCancelled { return }
            if stand == nil, let (alt, _) = schlange.gemerkt(Kalorienstand.self, "kalorien") {
                stand = alt
                if let angaben = alt.angaben { eingabe = Kalorieneingabe(angaben) }
            }
            fehler = "Der Server ist gerade nicht erreichbar. Ändern geht nur im Heimnetz. (\(Api.text(error)))"
        }
        geladen = true
    }

    private func speichern() async {
        if let grund = eingabe.fehler() {
            fehler = grund
            return
        }
        speichert = true
        defer { speichert = false }
        do {
            let api = try zustand.api()
            let neu = try await api.lesen(Kalorienstand.self, "PUT", "/api/kalorien/profil", json: eingabe.json)
            stand = neu
            if let angaben = neu.angaben { eingabe = Kalorieneingabe(angaben) }
            verlauf = try? await api.lesen(Kalorienverlauf.self, "GET", "/api/kalorien/verlauf?tage=30")
            schlange.merken(neu, als: "kalorien")
            fehler = nil
        } catch {
            fehler = Api.text(error)
        }
    }

    private func loeschen() async {
        do {
            _ = try await zustand.api().daten("DELETE", "/api/kalorien/profil")
            eingabe = Kalorieneingabe()
            await laden()
        } catch {
            fehler = Api.text(error)
        }
    }
}
