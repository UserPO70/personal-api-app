import SwiftUI
import Vision
import VisionKit

/// Schalter „zur letzten Mahlzeit“, nur sichtbar in den 30 Minuten nach der vorigen Erfassung.
private struct LetzteSchalter: View {
    @Binding var an: Bool
    @ObservedObject private var schlange = Warteschlange.shared

    var body: some View {
        if schlange.letzteMoeglich() {
            Section {
                Toggle("Zur letzten Mahlzeit hinzufügen", isOn: $an)
            } footer: {
                Text("Gehört zu dem, was du eben erfasst hast, statt eine neue Mahlzeit anzulegen.")
            }
        }
    }
}

private struct Fehlerzeile: View {
    let text: String?

    var body: some View {
        if let text {
            Section {
                Label(text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.orange)
            }
        }
    }
}

/// Reiht einen Eintrag ein und stößt das Senden an.
@MainActor
private func einreihen(_ eintrag: Eintrag, bild: Data? = nil, zurLetzten: Bool) throws {
    try Warteschlange.shared.aufnehmen(eintrag, bild: bild, zurLetzten: zurLetzten)
    Task { await Warteschlange.shared.senden() }
}

// MARK: Foto

struct FotoBlatt: View {
    let bild: UIImage
    @Environment(\.dismiss) private var schliessen
    @State private var notiz = ""
    @State private var gramm = ""
    @State private var zurLetzten = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: bild)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 260)
                }
                Section {
                    TextField("Notiz, z. B. große Portion", text: $notiz)
                    TextField("Gewicht in Gramm", text: $gramm)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Mehr (freiwillig)")
                } footer: {
                    Text("Mit gewogenem Gewicht rechnet Claude, statt die Menge zu schätzen.")
                }
                LetzteSchalter(an: $zurLetzten)
                Fehlerzeile(text: fehler)
            }
            .navigationTitle("Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") { senden() }
                }
            }
        }
    }

    private func senden() {
        let gewicht = Zahl.lesen(gramm)
        if !gramm.trimmingCharacters(in: .whitespaces).isEmpty && gewicht == nil {
            fehler = "Das Gewicht ist keine Zahl."
            return
        }
        guard let daten = Bild.jpeg(bild) else {
            fehler = "Das Foto lässt sich nicht verkleinern."
            return
        }
        let text = notiz.trimmingCharacters(in: .whitespacesAndNewlines)
        let eintrag = Eintrag(id: Eintrag.neueKennung(), art: .foto, zeit: Date(),
                              titel: text.isEmpty ? "Foto" : "Foto: \(text)",
                              notiz: text.isEmpty ? nil : text, gramm: gewicht)
        do {
            try einreihen(eintrag, bild: daten, zurLetzten: zurLetzten)
            schliessen()
        } catch {
            fehler = "Das Foto lässt sich nicht speichern: \(error.localizedDescription)"
        }
    }
}

// MARK: Text

struct TextBlatt: View {
    @Environment(\.dismiss) private var schliessen
    @State private var text = ""
    @State private var zurLetzten = false
    @State private var fehler: String?
    @FocusState private var tippt: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. Kaffee mit Milch", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($tippt)
                } footer: {
                    Text("Claude schätzt daraus die Nährwerte, auf deinem Server.")
                }
                LetzteSchalter(an: $zurLetzten)
                Fehlerzeile(text: fehler)
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") { senden() }
                        .disabled(sauber.isEmpty)
                }
            }
            .onAppear { tippt = true }
        }
    }

    private var sauber: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func senden() {
        let eintrag = Eintrag(id: Eintrag.neueKennung(), art: .text, zeit: Date(), titel: sauber, text: sauber)
        do {
            try einreihen(eintrag, zurLetzten: zurLetzten)
            schliessen()
        } catch {
            fehler = error.localizedDescription
        }
    }
}

// MARK: Barcode

struct BarcodeBlatt: View {
    static let einheiten = ["Standard", "g", "ml", "Portion", "Stück"]

    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.dismiss) private var schliessen
    @State private var code = ""
    @State private var auskunft: BarcodeAuskunft?
    @State private var sucht = false
    @State private var suchhinweis: String?
    @State private var einheit = "Standard"
    @State private var menge = ""
    @State private var notiz = ""
    @State private var zurLetzten = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                if code.isEmpty && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    Section {
                        QRScanner(gefunden: { text in
                            guard code.isEmpty else { return }
                            code = text
                            Task { await nachschlagen() }
                        }, arten: [.ean13, .ean8, .upce])
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Halte die Kamera auf den Strichcode der Packung.")
                    }
                }
                Section("Code") {
                    TextField("Ziffern unter dem Strichcode", text: $code)
                        .keyboardType(.numberPad)
                    if !code.isEmpty {
                        Button("Nachschlagen") {
                            Task { await nachschlagen() }
                        }
                        .disabled(sucht || !Self.gueltig(code))
                        Button("Anderen Code scannen") {
                            code = ""
                            auskunft = nil
                            suchhinweis = nil
                        }
                    }
                }
                if sucht || auskunft != nil || suchhinweis != nil {
                    Section("Produkt") {
                        if sucht {
                            ProgressView()
                        } else if let produkt = auskunft?.produkt {
                            Text(produkt.bezeichnung ?? produkt.name ?? "Produkt ohne Namen")
                            if let kcal = produkt.je100?.kcal {
                                LabeledContent("je 100 g/ml", value: Zahl.kcal(kcal))
                            }
                            if let packung = produkt.packungsgroesse {
                                LabeledContent("Packung", value: packung)
                            }
                        } else if auskunft != nil {
                            Text("Bei Open Food Facts nicht gefunden. Es wird ohne Nährwerte gespeichert.")
                                .foregroundStyle(Color.secondary)
                        } else if let suchhinweis {
                            Text(suchhinweis)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                Section {
                    Picker("Einheit", selection: $einheit) {
                        ForEach(waehlbar, id: \.self) { Text($0) }
                    }
                    if einheit != "Standard" {
                        TextField("Menge", text: $menge)
                            .keyboardType(.decimalPad)
                    }
                    if let produkt = auskunft?.produkt {
                        LabeledContent("Ergibt", value: vorschau(produkt))
                    }
                } header: {
                    Text("Menge")
                } footer: {
                    Text(mengenhinweis)
                }
                Section {
                    TextField("Notiz, z. B. zum Abendbrot", text: $notiz)
                } footer: {
                    Text("Wird nur dazugeschrieben und ändert die Nährwerte nicht.")
                }
                LetzteSchalter(an: $zurLetzten)
                Fehlerzeile(text: fehler)
            }
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Eintragen") { eintragen() }
                        .disabled(!Self.gueltig(code))
                }
            }
        }
    }

    /// Nur Einheiten, mit denen der Server für dieses Produkt rechnen kann. Ohne Auskunft alle.
    private var waehlbar: [String] {
        guard let produkt = auskunft?.produkt else { return Self.einheiten }
        return ["Standard"] + produkt.einheiten
    }

    private var mengenhinweis: String {
        guard let auskunft else {
            return "Standard: eine Portion laut Packung, sonst 100 g. Ob Portion und Stück für dieses Produkt gehen, zeigt sich erst beim Nachschlagen."
        }
        guard let produkt = auskunft.produkt else {
            return "Für ein unbekanntes Produkt gibt es keine Nährwerte, egal mit welcher Einheit."
        }
        var teile = ["Standard: \(produkt.portion == nil ? "100 g" : "eine Portion (\(Zahl.text(produkt.standardGramm)) g)")."]
        let fehlt = ["Portion", "Stück"].filter { produkt.groesse($0) == nil }
        if !fehlt.isEmpty {
            teile.append("\(fehlt.joined(separator: " und ")) fehlt, weil die Packung dafür keine Größe nennt.")
        } else if produkt.stueck == nil {
            teile.append("Ein Stück zählt wie eine Portion, weil die Packung kein Stückgewicht nennt.")
        }
        return teile.joined(separator: " ")
    }

    private func vorschau(_ produkt: BarcodeAuskunft.Produkt) -> String {
        let gewaehlt = einheit == "Standard" ? nil : einheit
        guard let kcal = produkt.kcal(menge: Zahl.lesen(menge), einheit: gewaehlt) else {
            return gewaehlt == nil ? "keine Nährwerte bekannt" : "–"
        }
        return Zahl.kcal(kcal)
    }

    /// Wie am Server: 8, 12, 13 oder 14 Ziffern.
    static func gueltig(_ code: String) -> Bool {
        let sauber = code.trimmingCharacters(in: .whitespaces)
        return [8, 12, 13, 14].contains(sauber.count) && sauber.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private func nachschlagen() async {
        let gesucht = code.trimmingCharacters(in: .whitespaces)
        guard Self.gueltig(gesucht) else {
            suchhinweis = "Ein Barcode hat 8, 12, 13 oder 14 Ziffern."
            return
        }
        sucht = true
        defer { sucht = false }
        do {
            let neu = try await zustand.api().lesen(BarcodeAuskunft.self, "GET", "/api/essen/barcode/\(gesucht)")
            auskunft = neu
            suchhinweis = nil
            // Eine Einheit, die es für dieses Produkt nicht gibt, bleibt nicht gewählt.
            if let produkt = neu.produkt, einheit != "Standard", !produkt.einheiten.contains(einheit) {
                einheit = "Standard"
            }
        } catch {
            auskunft = nil
            suchhinweis = "Der Server ist gerade nicht erreichbar. Das Produkt wird beim Senden nachgeschlagen."
        }
    }

    private func eintragen() {
        let sauber = code.trimmingCharacters(in: .whitespaces)
        var anzahl: Double?
        if einheit != "Standard" {
            guard let wert = Zahl.lesen(menge) else {
                fehler = "Bitte eine Menge eingeben."
                return
            }
            anzahl = wert
        }
        let name = auskunft?.produkt?.bezeichnung ?? auskunft?.produkt?.name ?? "Barcode \(sauber)"
        let bemerkung = notiz.trimmingCharacters(in: .whitespacesAndNewlines)
        let eintrag = Eintrag(id: Eintrag.neueKennung(), art: .barcode, zeit: Date(), titel: name,
                              notiz: bemerkung.isEmpty ? nil : bemerkung, barcode: sauber, menge: anzahl, einheit: einheit == "Standard" ? nil : einheit)
        do {
            try einreihen(eintrag, zurLetzten: zurLetzten)
            schliessen()
        } catch {
            fehler = error.localizedDescription
        }
    }
}

// MARK: Favoriten

struct FavoritenBlatt: View {
    private static let faktoren: [Double] = [0.5, 1, 1.5, 2]
    private static let faktorNamen: [Double: String] = [0.5: "½", 1: "1", 1.5: "1½", 2: "2"]

    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.dismiss) private var schliessen
    @State private var favoriten: [Favoritenliste.Favorit] = []
    @State private var geladen = false
    @State private var standVon: Date?
    @State private var faktor = 1.0
    @State private var zurLetzten = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Portionen") {
                    Picker("Portionen", selection: $faktor) {
                        ForEach(Self.faktoren, id: \.self) { wert in
                            Text(Self.faktorNamen[wert] ?? Zahl.text(wert)).tag(wert)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    if !geladen {
                        ProgressView()
                    } else if favoriten.isEmpty {
                        Text("Noch keine Favoriten. Du legst sie im Dashboard auf der Essen-Seite an.")
                            .foregroundStyle(Color.secondary)
                    }
                    ForEach(favoriten) { favorit in
                        Button {
                            waehlen(favorit)
                        } label: {
                            HStack {
                                Text(favorit.name)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Text(Zahl.kcal(favorit.summe?.kcal.map { $0 * faktor }))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Antippen zum Eintragen")
                } footer: {
                    if let standVon {
                        Text("Server nicht erreichbar. Liste von \(standVon.formatted(date: .abbreviated, time: .shortened)).")
                    }
                }
                LetzteSchalter(an: $zurLetzten)
                Fehlerzeile(text: fehler)
            }
            .navigationTitle("Favoriten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
            }
            .task { await laden() }
        }
    }

    private func laden() async {
        do {
            let liste = try await zustand.api().lesen(Favoritenliste.self, "GET", "/api/essen/favoriten")
            favoriten = liste.favoriten
            standVon = nil
            Warteschlange.shared.merken(liste, als: "favoriten")
        } catch {
            if let (alt, wann) = Warteschlange.shared.gemerkt(Favoritenliste.self, "favoriten") {
                favoriten = alt.favoriten
                standVon = wann
            } else {
                fehler = "Die Favoriten lassen sich gerade nicht laden: \(Api.text(error))"
            }
        }
        geladen = true
    }

    private func waehlen(_ favorit: Favoritenliste.Favorit) {
        let titel = faktor == 1 ? favorit.name : "\(favorit.name) × \(Zahl.text(faktor))"
        let eintrag = Eintrag(id: Eintrag.neueKennung(), art: .favorit, zeit: Date(), titel: titel,
                              favorit: favorit.name, faktor: faktor == 1 ? nil : faktor)
        do {
            try einreihen(eintrag, zurLetzten: zurLetzten)
            schliessen()
        } catch {
            fehler = error.localizedDescription
        }
    }
}

// MARK: Zustimmung

/// Fragt, bevor Fotos oder Texte gesendet werden, die der Server an Claude weitergibt.
struct ZustimmungView: View {
    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Fotoanalyse mit Claude")
                .font(.title2.bold())
            Text("Deine Mahlzeiten gehen an deinen eigenen Server. Fotos und Texte schickt dein Server zur Schätzung der Nährwerte an Claude von Anthropic, über dein eigenes Claude-Konto. Barcodes schlägt dein Server bei Open Food Facts nach. Der Anbieter dieser App bekommt nichts davon.")
            Text("Ohne Zustimmung kannst du Barcode und Favoriten nutzen. Du kannst das jederzeit in den Einstellungen ändern.")
                .foregroundStyle(Color.secondary)
            Spacer()
            Button {
                zustand.zustimmung = .ja
                schliessen()
            } label: {
                Text("Zustimmen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                zustand.zustimmung = .nein
                schliessen()
            } label: {
                Text("Ohne Fotoanalyse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }
}
