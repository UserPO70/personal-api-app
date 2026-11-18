import SwiftUI

/// Erfassen per Barcode, Text, Favorit und Mediathek, die Warteschlange und die Mahlzeiten des Essenstags. Der Foto-Knopf steht auf „Heute“.
struct EssenView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var tag: Essenstag?
    @State private var standVon: Date?
    /// Läuft mit, damit „Eben erfasst“ nach 30 Minuten von selbst verschwindet.
    @State private var jetzt = Date()

    var body: some View {
        NavigationStack {
            AppListe {
                if zustand.demo {
                    Section {
                        Label("Demo: ausgedachte Daten, kein Server", systemImage: "theatermasks")
                            .foregroundStyle(Color.text2)
                    }
                }
                Section {
                    Erfassen(umfang: .uebrige)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if !zustand.demo && schlange.letzteMoeglich(jetzt: jetzt) {
                    Section {
                        Erfassen(umfang: .ergaenzen)
                    } footer: {
                        Text("Noch bis \(ergaenzenBis) kann ein Foto zu dieser Mahlzeit dazukommen.")
                    }
                }
                if let meldung = schlange.meldung {
                    Section {
                        Label(meldung, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.warnung)
                    }
                }
                if !schlange.eintraege.isEmpty {
                    warteschlange
                }
                if !schlange.analysen.isEmpty {
                    analysen
                }
                essenstag
            }
            .navigationTitle("Essen")
            .refreshable {
                await schlange.senden(alle: true)
                await schlange.analysenPruefen()
                await laden()
            }
        }
        .task {
            await laden()
            await schlange.senden()
        }
        .onChange(of: schlange.neuesAmServer) {
            Task { await laden() }
        }
        .task {
            while !Task.isCancelled {
                jetzt = Date()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private var ergaenzenBis: String {
        let ende = (schlange.letzte?.zeit ?? jetzt).addingTimeInterval(Warteschlange.fensterLetzte)
        return ende.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Warteschlange

    private var warteschlange: some View {
        Section {
            ForEach(schlange.eintraege) { eintrag in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: eintrag.stand == .fehlgeschlagen ? "exclamationmark.circle.fill" : eintrag.symbol)
                        .foregroundStyle(eintrag.stand == .fehlgeschlagen ? Color.fehler : Color.text2)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eintrag.titel)
                            .lineLimit(2)
                        Text(standText(eintrag))
                            .font(.footnote)
                            .foregroundStyle(Color.text2)
                    }
                    Spacer(minLength: 0)
                    // Ein sichtbares Menü statt Wischen: Wischen wechselt zwischen den Tabs.
                    Menu {
                        if eintrag.stand == .fehlgeschlagen {
                            Button("Erneut senden", systemImage: "arrow.clockwise") {
                                schlange.erneut(eintrag.id)
                                Task { await schlange.senden(alle: true) }
                            }
                        }
                        Button("Löschen", systemImage: "trash", role: .destructive) { schlange.loeschen(eintrag.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(Color.text2)
                    }
                    .accessibilityLabel("Aktionen für \(eintrag.titel)")
                }
            }
            Button(schlange.sendet ? "Sendet …" : "Jetzt senden") {
                Task { await schlange.senden(alle: true) }
            }
            .disabled(schlange.sendet || schlange.wartend == 0)
        } header: {
            Text("Warteschlange")
        } footer: {
            Text("Wird gesendet, sobald dein Server erreichbar ist.")
        }
    }

    private func standText(_ eintrag: Eintrag) -> String {
        let uhrzeit = eintrag.zeit.formatted(date: .omitted, time: .shortened)
        switch eintrag.stand {
        case .fehlgeschlagen:
            return "Fehlgeschlagen: \(eintrag.hinweis ?? "vom Server abgelehnt")"
        case .wartet:
            if let hinweis = eintrag.hinweis { return "\(uhrzeit) · wartet · \(hinweis)" }
            return "\(uhrzeit) · wartet"
        }
    }

    private var analysen: some View {
        Section {
            ForEach(schlange.analysen) { analyse in
                HStack(alignment: .top, spacing: 12) {
                    if analyse.laeuft {
                        ProgressView()
                            .frame(width: 24)
                    } else {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Color.warnung)
                            .frame(width: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(analyse.titel)
                            .lineLimit(2)
                        Text(analyseText(analyse))
                            .font(.footnote)
                            .foregroundStyle(Color.text2)
                    }
                    Spacer(minLength: 0)
                    if !analyse.laeuft {
                        Button {
                            schlange.analyseAusblenden(analyse.auftrag)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.title3)
                                .foregroundStyle(Color.text2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Ausblenden")
                    }
                }
            }
        } header: {
            Text("Beim Server")
        } footer: {
            Text("Claude schätzt die Nährwerte auf deinem Server. Das dauert meist unter einer Minute.")
        }
    }

    private func analyseText(_ analyse: Analyse) -> String {
        switch analyse.status {
        case "wartet": return "angekommen, wartet auf die Schätzung"
        case "laeuft": return "wird gerade geschätzt"
        case "kein_essen": return "Kein Essen erkannt"
        case "fehler": return "Schätzung fehlgeschlagen. Im Dashboard unter Essen kannst du sie wiederholen."
        default: return analyse.status
        }
    }

    // MARK: Essenstag

    private var essenstag: some View {
        Section {
            if let tag {
                // Die Kalorien des Tages stehen groß auf „Heute“; hier nur die Nährwerte in einer Zeile.
                Text("Eiweiß \(Zahl.gramm(tag.summe?.eiweiss)) · Kohlenhydrate \(Zahl.gramm(tag.summe?.kohlenhydrate)) · Fett \(Zahl.gramm(tag.summe?.fett))")
                    .font(.footnote)
                    .foregroundStyle(Color.text2)
                if tag.mahlzeiten.isEmpty {
                    Text("Noch nichts eingetragen.")
                        .foregroundStyle(Color.text2)
                }
                ForEach(tag.mahlzeiten) { mahlzeit in
                    NavigationLink {
                        MahlzeitView(mahlzeit: mahlzeit)
                            .alsUnterseite()
                    } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(mahlzeit.uhrzeit ?? "")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Color.text2)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mahlzeit.titel)
                                .lineLimit(2)
                            if let art = mahlzeit.art {
                                Text(art)
                                    .font(.footnote)
                                    .foregroundStyle(Color.text2)
                            }
                        }
                        Spacer()
                        Text((mahlzeit.geschaetzt ? "≈ " : "") + Zahl.kcal(mahlzeit.summe?.kcal))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.text2)
                    }
                    }
                    .disabled(zustand.demo)
                }
            } else {
                Text("Der Tag lässt sich gerade nicht laden.")
                    .foregroundStyle(Color.text2)
            }
        } header: {
            Text(tag.map { "Essenstag \($0.tag)" } ?? "Essenstag")
        } footer: {
            if let standVon {
                Text("Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened)).")
            } else {
                Text("Geschätzte Werte können um 20 bis 30 % abweichen.")
            }
        }
    }

    private func laden() async {
        if zustand.demo {
            tag = Essenstag(tag: "Demo", anzahl: 2, summe: Naehrwerte(kcal: 789, eiweiss: 24.5, kohlenhydrate: 137, fett: 12.7), mahlzeiten: [
                Mahlzeit(id: 1, uhrzeit: "08:00", quelle: "barcode", notiz: nil, art: "Frühstück",
                         bestandteile: [Bestandteil(lebensmittel: "Müsli", menge: 80, einheit: "g", kcal: 304)],
                         summe: Naehrwerte(kcal: 304, eiweiss: 8, kohlenhydrate: 48, fett: 6.8)),
                Mahlzeit(id: 2, uhrzeit: "12:30", quelle: "foto", notiz: nil, art: "Mittag",
                         bestandteile: [Bestandteil(lebensmittel: "Spaghetti", menge: 250, einheit: "g", kcal: 395),
                                        Bestandteil(lebensmittel: "Tomatensoße", menge: 150, einheit: "ml", kcal: 90)],
                         summe: Naehrwerte(kcal: 485, eiweiss: 16.5, kohlenhydrate: 89, fett: 5.9)),
            ])
            standVon = nil
            return
        }
        do {
            let neu = try await zustand.api().lesen(Essenstag.self, "GET", "/api/essen/tag?tag=\(Essenstag.heute())")
            tag = neu
            standVon = nil
            schlange.merken(neu, als: "essenstag")
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Essenstag.self, "essenstag") {
                tag = alt
                standVon = wann
            }
        }
    }
}
