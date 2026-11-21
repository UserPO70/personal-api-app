import SwiftUI

/// Rückblick auf eine Kalenderwoche oder einen Kalendermonat, verglichen mit der Vorperiode. Gleiche Zahlen wie die
/// Seite „Rückblick“ im Dashboard; gerechnet wird am Server (GET /api/rueckblick).
struct RueckblickView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var art = "woche"
    @State private var tag = Kalendertag.heute()
    @State private var daten: Rueckblick?
    @State private var standVon: Date?
    @State private var fehler: String?

    var body: some View {
        AppListe {
            Section {
                Picker("Zeitraum", selection: $art) {
                    Text("Woche").tag("woche")
                    Text("Monat").tag("monat")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let daten {
                kopf(daten)
                inhalt(daten)
            } else if let fehler {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warnung)
                }
            } else {
                Section { ProgressView() }
            }
        }
        .navigationTitle("Rückblick")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await laden() }
        .task(id: "\(art)|\(tag)") { await laden() }
    }

    // MARK: Kopf

    private func kopf(_ d: Rueckblick) -> some View {
        Section {
            HStack(spacing: Abstand.eng) {
                Button {
                    tag = d.zurueck
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(d.art == "monat" ? "Monat davor" : "Woche davor")
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text(d.titel)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if d.laeuftNoch {
                        Text("läuft noch · \(d.tageAusgewertet) von \(d.tageGesamt) Tagen")
                            .font(.footnote)
                            .foregroundStyle(Color.text2)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    tag = d.weiter
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(!d.weiterMoeglich(heute: Kalendertag.heute()))
                .accessibilityLabel(d.art == "monat" ? "Monat danach" : "Woche danach")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: Inhalt

    @ViewBuilder
    private func inhalt(_ d: Rueckblick) -> some View {
        if d.leer {
            Section {
                Text("In diesem Zeitraum gibt es keine Daten.")
                    .foregroundStyle(Color.text2)
            }
        }
        let gesundheit = d.mitDaten(Rueckblick.gesundheit)
        if !gesundheit.isEmpty {
            Section("Gesundheit") {
                ForEach(gesundheit) { k in
                    kennzahlZeile(k, d, zusatz: k.schluessel == "gewicht_kg" ? gewichtZusatz(d.gewicht) : nil)
                }
            }
        }
        ernaehrung(d)
        kalorienziel(d)
        orteUndWege(d)
        pcZeit(d)
        if let internet = d.kennzahl("internet_mb") {
            Section("Internet") {
                kennzahlZeile(internet, d)
            }
        }
        if !d.leer {
            Section {
            } footer: {
                Text(fusszeile(d))
            }
        }
    }

    @ViewBuilder
    private func ernaehrung(_ d: Rueckblick) -> some View {
        let werte = d.mitDaten(Rueckblick.ernaehrung)
        let fenster = d.essen.fenster
        if !werte.isEmpty || fenster.jetzt.tage > 0 {
            Section("Essen") {
                ForEach(werte) { k in
                    kennzahlZeile(k, d)
                }
                if fenster.jetzt.tage > 0 {
                    if let erste = fenster.jetzt.erste {
                        zeile("Erste Mahlzeit", wert: "Ø \(erste)",
                              unter: fenster.vorher.erste.map { "\(d.vorperiode) Ø \($0)" } ?? "\(d.vorperiode): keine Daten")
                    }
                    if let letzte = fenster.jetzt.letzte {
                        zeile("Letzte Mahlzeit", wert: "Ø \(letzte)",
                              unter: fenster.vorher.letzte.map { "\(d.vorperiode) Ø \($0)" } ?? "\(d.vorperiode): keine Daten")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func kalorienziel(_ d: Rueckblick) -> some View {
        if let ziel = d.essen.ziel, ziel.jetzt.tageMitZiel > 0 {
            let a = ziel.jetzt, b = ziel.vorher
            Section {
                if let kcal = a.zielSchnittKcal {
                    zeile("Ziel", wert: "Ø \(Rueckblicktext.wert(kcal, schluessel: "kcal"))",
                          unter: b.zielSchnittKcal.map { "\(d.vorperiode) Ø \(Rueckblicktext.wert($0, schluessel: "kcal"))" }
                              ?? "\(d.vorperiode): kein Ziel")
                }
                if let abweichung = abweichungText(a) {
                    zeile("Abweichung", wert: "Ø \(abweichung)",
                          unter: abweichungText(b).map { "\(d.vorperiode) Ø \($0)" } ?? "\(d.vorperiode): keine Daten")
                }
                if a.tageVollstaendig > 0, let im = a.tageImZielbereich {
                    zeile("Im Zielbereich", wert: "\(im) von \(Rueckblicktext.tage(a.tageVollstaendig))",
                          unter: zielbereichVorher(b, vorperiode: d.vorperiode),
                          vergleich: a.anteilImZielbereichProzent.map { "\(Int($0.rounded())) %" })
                }
            } header: {
                Text("Kalorienziel")
            } footer: {
                Text(zielFuss(ziel))
            }
        }
    }

    @ViewBuilder
    private func orteUndWege(_ d: Rueckblick) -> some View {
        let werte = d.mitDaten(Rueckblick.unterwegs)
        let fahrten = d.jetzt.fahrten
        if !werte.isEmpty || d.jetzt.orteAnzahl > 0 {
            Section("Orte und Wege") {
                ForEach(werte) { k in
                    kennzahlZeile(k, d, zusatz: k.schluessel == "fahrten" && fahrten.anzahl > 0
                                  ? "zusammen \(fahrten.anzahl) · \(Dauertext.minuten(fahrten.minuten)) · \(Dauertext.kilometer(fahrten.streckeKm))"
                                  : nil)
                }
                ForEach(d.jetzt.orte.prefix(5)) { ort in
                    zeile(ort.name, wert: Dauertext.minuten(ort.minuten), unter: nil)
                }
                if d.jetzt.orteAnzahl > 5 {
                    Text("und \(d.jetzt.orteAnzahl - 5) weitere Orte")
                        .font(.footnote)
                        .foregroundStyle(Color.text3)
                }
                if !d.jetzt.neueOrte.isEmpty {
                    zeile("Neu", wert: "", unter: d.jetzt.neueOrte.joined(separator: ", "))
                }
            }
            if !fahrten.haeufigste.isEmpty {
                Section("Häufigste Strecken") {
                    ForEach(fahrten.haeufigste) { strecke in
                        zeile(strecke.strecke, wert: "\(strecke.anzahl)×", unter: nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pcZeit(_ d: Rueckblick) -> some View {
        let gesamt = d.kennzahl("pc_minuten")
        let kategorien = d.pc.kategorien.filter { ($0.jetzt.summe ?? 0) > 0 }.prefix(5)
        if gesamt != nil || !kategorien.isEmpty || d.pc.fehler != nil {
            Section("PC-Zeit") {
                if let gesamt {
                    kennzahlZeile(gesamt, d)
                }
                ForEach(Array(kategorien)) { kategorie in
                    zeile(kategorie.name,
                          wert: kategorie.jetzt.schnitt.map { "Ø \(Dauertext.minuten($0))" } ?? "",
                          unter: Rueckblicktext.vorher(kategorie.vorher, schluessel: "pc_minuten", vorperiode: d.vorperiode),
                          vergleich: Rueckblicktext.vergleich(kategorie.vergleich, schluessel: "pc_minuten"))
                }
                if let fehler = d.pc.fehler {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.warnung)
                }
            }
        }
    }

    // MARK: Zeilen

    private func kennzahlZeile(_ k: Rueckblick.Kennzahl, _ d: Rueckblick, zusatz: String? = nil) -> some View {
        let vorher = Rueckblicktext.vorher(k.vorher, schluessel: k.schluessel, vorperiode: d.vorperiode)
        return zeile(k.name,
                     wert: k.jetzt.schnitt.map { "Ø \(Rueckblicktext.wert($0, schluessel: k.schluessel))" } ?? "",
                     unter: [vorher, zusatz].compactMap { $0 }.joined(separator: " · "),
                     vergleich: Rueckblicktext.vergleich(k.vergleich, schluessel: k.schluessel))
    }

    /// Name links, Wert rechts; darunter klein die Vorperiode und rechts der Vergleich. Nur Textfarben.
    private func zeile(_ name: String, wert: String, unter: String?, vergleich: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.eng) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let unter, !unter.isEmpty {
                    Text(unter)
                        .font(.footnote)
                        .foregroundStyle(Color.text3)
                }
            }
            Spacer(minLength: Abstand.eng)
            VStack(alignment: .trailing, spacing: 2) {
                if !wert.isEmpty {
                    Text(wert)
                        .monospacedDigit()
                }
                if let vergleich {
                    Text(vergleich)
                        .font(.footnote)
                        .foregroundStyle(Color.text2)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Texte

    private func gewichtZusatz(_ gewicht: Rueckblick.Gewicht) -> String? {
        var teile: [String] = []
        if let kg = gewicht.veraenderung?.kg {
            let zeichen = kg > 0.05 ? "+" : kg < -0.05 ? "−" : "±"
            teile.append("Verlauf \(zeichen)\(Rueckblicktext.komma(abs(kg), stellen: 1)) kg")
        }
        teile.append(gewicht.messungen == 1 ? "1 Messung" : "\(gewicht.messungen) Messungen")
        return teile.joined(separator: " · ")
    }

    private func abweichungText(_ teil: Rueckblick.Essen.Ziel.Teil) -> String? {
        guard let kcal = teil.abweichungSchnittKcal else { return nil }
        var text = Rueckblicktext.mitVorzeichen(kcal, einheit: "kcal")
        if let prozent = teil.abweichungSchnittProzent {
            let zeichen = prozent > 0.05 ? "+" : prozent < -0.05 ? "−" : "±"
            text += " (\(zeichen)\(Rueckblicktext.komma(abs(prozent), stellen: 1)) %)"
        }
        return text
    }

    private func zielbereichVorher(_ b: Rueckblick.Essen.Ziel.Teil, vorperiode: String) -> String {
        guard b.tageVollstaendig > 0, let im = b.tageImZielbereich else { return "\(vorperiode): keine Daten" }
        let anteil = b.anteilImZielbereichProzent.map { " (\(Int($0.rounded())) %)" } ?? ""
        return "\(vorperiode) \(im) von \(Rueckblicktext.tage(b.tageVollstaendig))\(anteil)"
    }

    private func zielFuss(_ ziel: Rueckblick.Essen.Ziel) -> String {
        var text = "Nur vollständige Essenstage mit Ziel. Im Zielbereich = höchstens "
            + "\(Int(ziel.zielbereichProzent.rounded())) % über oder unter dem Ziel des Tages."
        var fehlt: [String] = []
        if let n = ziel.jetzt.tageUnvollstaendig, n > 0 {
            fehlt.append(n == 1 ? "1 unvollständiger Tag" : "\(n) unvollständige Tage")
        }
        if let n = ziel.jetzt.tageEssenOhneZiel, n > 0 {
            fehlt.append(n == 1 ? "1 Tag mit Essen, aber ohne Ziel" : "\(n) Tage mit Essen, aber ohne Ziel")
        }
        if !fehlt.isEmpty { text += " Nicht mitgezählt: \(fehlt.joined(separator: ", "))." }
        return text
    }

    private func fusszeile(_ d: Rueckblick) -> String {
        var text = "Ø = Durchschnitt je Tag mit Daten; Tage ohne Daten zählen nicht als 0. "
            + "Die Pfeile vergleichen mit dem Durchschnitt \(d.art == "monat" ? "des Vormonats" : "der Vorwoche")."
        if let standVon {
            text += " Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }

    // MARK: Laden

    private func laden() async {
        if zustand.demo {
            daten = Rueckblick.demo(art: art)
            return
        }
        let merkname = "rueckblick-\(art)-\(tag)"
        do {
            let neu = try await zustand.api().lesen(Rueckblick.self, "GET", "/api/rueckblick?art=\(art)&tag=\(tag)")
            daten = neu
            standVon = nil
            fehler = nil
            schlange.merken(neu, als: merkname)
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Rueckblick.self, merkname) {
                daten = alt
                standVon = wann
            } else {
                daten = nil
                fehler = Api.text(error)
            }
        }
    }
}
