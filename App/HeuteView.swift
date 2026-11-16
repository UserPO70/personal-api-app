import SwiftUI

/// GET /api/app/heute, nur die Teile für den Überblick.
struct Tagesueberblick: Codable, Equatable {
    struct Uebersicht: Codable, Equatable {
        struct Schlaf: Codable, Equatable {
            var minuten: Double?
        }

        var schritte: Double?
        var strecke: Double?
        var stockwerke: Double?
        var pcMinuten: Double?
        var schlaf: Schlaf?

        enum CodingKeys: String, CodingKey {
            case schritte, stockwerke, schlaf
            case strecke = "strecke_km"
            case pcMinuten = "pc_minuten"
        }
    }

    struct Essen: Codable, Equatable {
        struct Ziel: Codable, Equatable {
            var kcal: Double
            var gegessen: Double?

            enum CodingKeys: String, CodingKey {
                case kcal
                case gegessen = "gegessen_kcal"
            }
        }

        var tag: String?
        var anzahl: Int?
        var summe: Naehrwerte?
        var ziel: Ziel?
    }

    struct Koerper: Codable, Equatable {
        struct Gewicht: Codable, Equatable {
            var kg: Double
            var tag: String?
        }

        var gewicht: Gewicht?
    }

    var tag: String
    var uebersicht: Uebersicht?
    var essen: Essen?
    var koerper: Koerper?
}

enum Dauertext {
    /// „9 h 40 min“, „45 min“.
    static func minuten(_ minuten: Double) -> String {
        let ganz = Int(minuten.rounded())
        if ganz < 60 { return "\(ganz) min" }
        return ganz % 60 == 0 ? "\(ganz / 60) h" : "\(ganz / 60) h \(ganz % 60) min"
    }

    static func kilometer(_ km: Double) -> String {
        String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }

    static func ganzzahl(_ wert: Double) -> String {
        // Mit Tausenderpunkt wie im Dashboard: 9.151
        let zahl = Int(wert.rounded())
        guard zahl >= 1000 else { return "\(zahl)" }
        return "\(zahl / 1000).\(String(format: "%03d", zahl % 1000))"
    }

    /// „2 Einträge warten auf den Server · 1 wird geschätzt“
    static func wartend(eintraege: Int, analysen: Int) -> String {
        var teile: [String] = []
        if eintraege == 1 { teile.append("1 Eintrag wartet auf den Server") }
        if eintraege > 1 { teile.append("\(eintraege) Einträge warten auf den Server") }
        if analysen == 1 { teile.append("1 wird geschätzt") }
        if analysen > 1 { teile.append("\(analysen) werden geschätzt") }
        return teile.isEmpty ? "Im Tab Essen braucht etwas deinen Blick" : teile.joined(separator: " · ")
    }
}

/// Eine Kachel mit Symbol, Name und Wert. Die Bereichsfarbe sitzt nur im Symbol, der Text bleibt in den Textfarben.
struct Kachel: View {
    let name: String
    let wert: String
    let symbol: String
    let farbe: Color
    /// Die Kachel führt auf eine Unterseite: Dann steht rechts ein Pfeil.
    var oeffnet = false

    var body: some View {
        HStack(spacing: Abstand.eng) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(farbe)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Color.text2)
                Text(wert)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if oeffnet {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.text3)
                    .accessibilityHidden(true)
            }
        }
        .alsFlaeche(innen: Abstand.kachel)
        .accessibilityElement(children: .combine)
    }
}

/// Der Hauptbildschirm: der Tag auf einen Blick, möglichst ohne Scrollen, und unten in Daumenreichweite Essen erfassen.
struct HeuteView: View {
    /// Ein Wert des Tages für eine Kachel.
    private struct Wert: Identifiable {
        let kennzahl: Kennzahl
        let wert: String

        var id: String { kennzahl.rawValue }
    }

    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var tag: Tagesueberblick?
    @State private var standVon: Date?
    @State private var fehler: String?

    private let spalten = [GridItem(.flexible(), spacing: Abstand.kachel), GridItem(.flexible(), spacing: Abstand.kachel)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Abstand.kachel) {
                    if zustand.demo {
                        Label("Demo: ausgedachte Daten, kein Server", systemImage: "theatermasks")
                            .font(.footnote)
                            .foregroundStyle(Color.text2)
                    }
                    if !schlange.eintraege.isEmpty || schlange.analysen.contains(where: \.laeuft) {
                        Label(Dauertext.wartend(eintraege: schlange.eintraege.count,
                                                analysen: schlange.analysen.filter(\.laeuft).count),
                              systemImage: "tray.and.arrow.up")
                            .font(.footnote)
                            .foregroundStyle(Color.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let tag {
                        kalorien(tag)
                        LazyVGrid(columns: spalten, spacing: Abstand.kachel) {
                            ForEach(werte(tag)) { wert in
                                NavigationLink {
                                    KennzahlView(kennzahl: wert.kennzahl)
                                        .alsUnterseite()
                                } label: {
                                    Kachel(name: wert.kennzahl.name, wert: wert.wert, symbol: wert.kennzahl.symbol,
                                           farbe: wert.kennzahl.farbe, oeffnet: true)
                                }
                                .buttonStyle(.plain)
                            }
                            if !zustand.demo {
                                NavigationLink {
                                    KalorienView()
                                        .alsUnterseite()
                                } label: {
                                    Kachel(name: "Gewicht und Ziel",
                                           wert: tag.koerper?.gewicht.map { Gewichtstext.kg($0.kg) } ?? "eintragen",
                                           symbol: "scalemass", farbe: .gesundheit, oeffnet: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let standVon {
                            Text("Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.footnote)
                                .foregroundStyle(Color.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if let fehler {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.warnung)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView()
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, Abstand.rand)
                .padding(.vertical, Abstand.kachel)
            }
            .background(Color.grund)
            // Erfassen sitzt unten direkt über der Tab-Leiste, damit der Daumen den Foto-Knopf mit einer Hand erreicht.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Erfassen(umfang: .foto)
                    .padding(.horizontal, Abstand.rand)
                    .padding(.vertical, Abstand.eng)
                    .background(Color.grund)
            }
            .navigationTitle("Heute")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await schlange.senden(alle: true)
                await laden()
            }
            .task { await laden() }
            .onChange(of: schlange.neuesAmServer) {
                Task { await laden() }
            }
        }
    }

    private func kalorien(_ tag: Tagesueberblick) -> some View {
        VStack(alignment: .leading, spacing: Abstand.eng) {
            HStack(alignment: .firstTextBaseline) {
                Text(Zahl.kcal(tag.essen?.summe?.kcal))
                    .font(.title.bold().monospacedDigit())
                Spacer()
                if let ziel = tag.essen?.ziel {
                    Text("Ziel \(Zahl.kcal(ziel.kcal))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.text2)
                }
            }
            if let ziel = tag.essen?.ziel {
                ProgressView(value: Kalorientext.anteil(gegessen: tag.essen?.summe?.kcal, ziel: ziel.kcal))
                    .tint(Color.essen)
                Text(Kalorientext.offen(gegessen: tag.essen?.summe?.kcal, ziel: ziel.kcal))
                    .font(.footnote)
                    .foregroundStyle(Color.text2)
            } else {
                Text((tag.essen?.anzahl ?? 0) == 0 ? "Heute ist noch nichts eingetragen." : "Noch kein Kalorienziel festgelegt.")
                    .font(.footnote)
                    .foregroundStyle(Color.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alsFlaeche()
        .accessibilityElement(children: .combine)
    }

    /// Nur Werte, die es an dem Tag gibt. Was fehlt, nimmt keinen Platz weg.
    private func werte(_ tag: Tagesueberblick) -> [Wert] {
        var liste: [Wert] = []
        let uebersicht = tag.uebersicht
        if let schritte = uebersicht?.schritte {
            liste.append(Wert(kennzahl: .schritte, wert: Kennzahl.schritte.text(schritte)))
        }
        if let strecke = uebersicht?.strecke {
            liste.append(Wert(kennzahl: .strecke, wert: Kennzahl.strecke.text(strecke)))
        }
        if let stockwerke = uebersicht?.stockwerke {
            liste.append(Wert(kennzahl: .stockwerke, wert: Kennzahl.stockwerke.text(stockwerke)))
        }
        if let minuten = uebersicht?.schlaf?.minuten {
            liste.append(Wert(kennzahl: .schlaf, wert: Kennzahl.schlaf.text(minuten)))
        }
        if let minuten = uebersicht?.pcMinuten, minuten > 0 {
            liste.append(Wert(kennzahl: .pcZeit, wert: Kennzahl.pcZeit.text(minuten)))
        }
        return liste
    }

    private func laden() async {
        if zustand.demo {
            tag = Tagesueberblick(
                tag: "Demo",
                uebersicht: .init(schritte: 6240, strecke: 4.6, stockwerke: 8, pcMinuten: 95, schlaf: .init(minuten: 452)),
                essen: .init(tag: "Demo", anzahl: 2, summe: Naehrwerte(kcal: 789, eiweiss: 24.5, kohlenhydrate: 137, fett: 12.7),
                             ziel: .init(kcal: 2100, gegessen: 789)),
                koerper: nil)
            return
        }
        do {
            let neu = try await zustand.api().lesen(Tagesueberblick.self, "GET", "/api/app/heute")
            tag = neu
            standVon = nil
            fehler = nil
            schlange.merken(neu, als: "heute")
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Tagesueberblick.self, "heute") {
                tag = alt
                standVon = wann
            } else {
                fehler = Api.text(error)
            }
        }
    }
}

/// Für die Einstellungen: Name und Version des Servers und ob die Fotoanalyse bereit ist.
struct ServerAuskunft: View {
    @EnvironmentObject private var zustand: AppZustand
    @State private var info: Info?
    @State private var fehler: String?

    var body: some View {
        Group {
            if let info {
                LabeledContent("Name", value: info.name)
                LabeledContent("Version", value: info.version)
                LabeledContent("Fotoanalyse", value: info.claude?.bereit == true ? "bereit" : "nicht bereit")
            } else if let fehler {
                Label(fehler, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.warnung)
            } else {
                LabeledContent("Server", value: "wird abgefragt …")
            }
        }
        .task {
            do {
                info = try await zustand.api().lesen(Info.self, "GET", "/api/info")
                fehler = nil
            } catch {
                if Task.isCancelled { return }
                fehler = Api.text(error)
            }
        }
    }
}
