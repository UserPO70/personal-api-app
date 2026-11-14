import PhotosUI
import SwiftUI

/// Essen erfassen (Foto, Barcode, Text, Favorit), Warteschlange und der Essenstag.
struct EssenView: View {
    private struct Aufnahme {
        let id = UUID()
        let bild: UIImage
    }

    private enum Blatt: Identifiable {
        case foto(Aufnahme)
        case barcode, text, favoriten, zustimmung

        var id: String {
            switch self {
            case .foto(let aufnahme): return aufnahme.id.uuidString
            case .barcode: return "barcode"
            case .text: return "text"
            case .favoriten: return "favoriten"
            case .zustimmung: return "zustimmung"
            }
        }
    }

    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var tag: Essenstag?
    @State private var standVon: Date?
    /// Das heute geltende Kalorienziel, wenn eines festgelegt ist.
    @State private var ziel: Kalorienstand.Ziel?
    @State private var blatt: Blatt?
    @State private var kamera = false
    @State private var aufgenommen: UIImage?
    @State private var auswahl: PhotosPickerItem?
    @State private var hinweis: String?

    var body: some View {
        NavigationStack {
            List {
                if zustand.demo {
                    Section {
                        Label("Demo: ausgedachte Daten. Erfassen geht erst mit eigenem Server.", systemImage: "theatermasks")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    erfassen
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let meldung = schlange.meldung {
                    Section {
                        Label(meldung, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.orange)
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
        .task {
            // Solange Fotos oder Texte geschätzt werden, alle paar Sekunden nachsehen.
            while !Task.isCancelled {
                await schlange.analysenPruefen()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onChange(of: schlange.neuesAmServer) {
            Task { await laden() }
        }
        .onChange(of: auswahl) { _, neu in
            guard let neu else { return }
            auswahl = nil
            Task {
                if let daten = try? await neu.loadTransferable(type: Data.self), let bild = UIImage(data: daten) {
                    blatt = .foto(Aufnahme(bild: bild))
                } else {
                    hinweis = "Das Bild lässt sich nicht lesen."
                }
            }
        }
        .fullScreenCover(isPresented: $kamera, onDismiss: kameraZu) {
            Kamera { bild in
                aufgenommen = bild
                kamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $blatt) { blatt in
            switch blatt {
            case .foto(let aufnahme):
                FotoBlatt(bild: aufnahme.bild)
            case .barcode:
                BarcodeBlatt()
            case .text:
                TextBlatt()
            case .favoriten:
                FavoritenBlatt()
            case .zustimmung:
                ZustimmungView()
            }
        }
        .alert("Hinweis", isPresented: hinweisZeigen) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(hinweis ?? "")
        }
    }

    private var hinweisZeigen: Binding<Bool> {
        Binding(get: { hinweis != nil }, set: { if !$0 { hinweis = nil } })
    }

    // MARK: Erfassen

    private var erfassen: some View {
        VStack(spacing: 12) {
            Button {
                if claudeErlaubt() {
                    if Kamera.vorhanden {
                        kamera = true
                    } else {
                        hinweis = "Dieses Gerät hat keine Kamera. Nimm ein Foto aus der Mediathek."
                    }
                }
            } label: {
                Label("Foto", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                knopf("Barcode", "barcode.viewfinder") { blatt = .barcode }
                knopf("Text", "text.cursor") {
                    if claudeErlaubt() { blatt = .text }
                }
                knopf("Favorit", "star") { blatt = .favoriten }
            }

            if zustand.zustimmung == .ja {
                PhotosPicker(selection: $auswahl, matching: .images) {
                    Label("Foto aus der Mediathek", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
        .disabled(zustand.demo)
    }

    private func knopf(_ name: String, _ symbol: String, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(name)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    /// Foto und Text gehen über den Server an Claude: nur mit Zustimmung.
    private func claudeErlaubt() -> Bool {
        switch zustand.zustimmung {
        case .ja:
            return true
        case .offen:
            blatt = .zustimmung
            return false
        case .nein:
            hinweis = "Die Fotoanalyse ist ausgeschaltet. Du kannst sie in den Einstellungen einschalten. Barcode und Favoriten gehen auch so."
            return false
        }
    }

    private func kameraZu() {
        guard let bild = aufgenommen else { return }
        aufgenommen = nil
        blatt = .foto(Aufnahme(bild: bild))
    }

    // MARK: Warteschlange

    private var warteschlange: some View {
        Section {
            ForEach(schlange.eintraege) { eintrag in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: eintrag.stand == .fehlgeschlagen ? "exclamationmark.circle.fill" : eintrag.symbol)
                        .foregroundStyle(eintrag.stand == .fehlgeschlagen ? Color.red : Color.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eintrag.titel)
                            .lineLimit(2)
                        Text(standText(eintrag))
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Löschen", role: .destructive) { schlange.loeschen(eintrag.id) }
                    if eintrag.stand == .fehlgeschlagen {
                        Button("Erneut") {
                            schlange.erneut(eintrag.id)
                            Task { await schlange.senden(alle: true) }
                        }
                    }
                }
            }
            Button(schlange.sendet ? "Sendet …" : "Jetzt senden") {
                Task { await schlange.senden(alle: true) }
            }
            .disabled(schlange.sendet || schlange.wartend == 0)
        } header: {
            Text("Warteschlange")
        } footer: {
            Text("Wird gesendet, sobald dein Server erreichbar ist. Zum Löschen nach links wischen.")
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
                            .foregroundStyle(Color.orange)
                            .frame(width: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(analyse.titel)
                            .lineLimit(2)
                        Text(analyseText(analyse))
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Ausblenden") { schlange.analyseAusblenden(analyse.auftrag) }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(Zahl.kcal(tag.summe?.kcal))
                        .font(.title2.bold())
                    Text("Eiweiß \(Zahl.gramm(tag.summe?.eiweiss)) · Kohlenhydrate \(Zahl.gramm(tag.summe?.kohlenhydrate)) · Fett \(Zahl.gramm(tag.summe?.fett))")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                if let ziel {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Kalorientext.anteil(gegessen: tag.summe?.kcal, ziel: ziel.kcal))
                            .tint(Color.essen)
                        Text("Ziel \(Zahl.kcal(ziel.kcal)) · \(Kalorientext.offen(gegessen: tag.summe?.kcal, ziel: ziel.kcal))")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !zustand.demo {
                    NavigationLink {
                        KalorienView()
                    } label: {
                        Label(ziel == nil ? "Kalorienziel festlegen" : "Kalorienrechner", systemImage: "target")
                    }
                }
                if tag.mahlzeiten.isEmpty {
                    Text("Noch nichts eingetragen.")
                        .foregroundStyle(Color.secondary)
                }
                ForEach(tag.mahlzeiten) { mahlzeit in
                    HStack(alignment: .top, spacing: 12) {
                        Text(mahlzeit.uhrzeit ?? "")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mahlzeit.titel)
                                .lineLimit(2)
                            if let art = mahlzeit.art {
                                Text(art)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        Spacer()
                        Text(Zahl.kcal(mahlzeit.summe?.kcal))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                    }
                }
            } else {
                Text("Der Tag lässt sich gerade nicht laden.")
                    .foregroundStyle(Color.secondary)
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
            // Ältere Server kennen den Kalorienrechner nicht: Dann bleibt es ohne Ziel.
            if let stand = try? await zustand.api().lesen(Kalorienstand.self, "GET", "/api/kalorien/profil") {
                ziel = stand.ziel
                schlange.merken(stand, als: "kalorien")
            }
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Essenstag.self, "essenstag") {
                tag = alt
                standVon = wann
            }
            if let (alt, _) = schlange.gemerkt(Kalorienstand.self, "kalorien") {
                ziel = alt.ziel
            }
        }
    }
}
