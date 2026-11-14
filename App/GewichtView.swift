import Charts
import SwiftUI

/// GET /api/koerper/gewicht/verlauf
struct Gewichtsverlauf: Codable, Equatable {
    struct Tag: Codable, Equatable, Identifiable {
        var tag: String
        var kg: Double?
        var mittel: Double?

        var id: String { tag }

        enum CodingKeys: String, CodingKey {
            case tag, kg
            case mittel = "mittel_7_tage"
        }
    }

    struct Messung: Codable, Equatable, Identifiable {
        var id: Int
        var kg: Double
        var tag: String?
        var notiz: String?
    }

    struct Veraenderung: Codable, Equatable {
        var kgProWoche: Double?
        var tageMitMessung: Int?
        var grund: String?

        enum CodingKeys: String, CodingKey {
            case grund
            case kgProWoche = "kg_pro_woche"
            case tageMitMessung = "tage_mit_messung"
        }
    }

    var tage: [Tag]
    var messungen: [Messung]
    var letzte: Messung?
    var veraenderung: Veraenderung?

    /// Tag „2026-03-15“ als Datum (Mittag, damit die Zeitumstellung nichts verschiebt).
    static func datum(_ tag: String) -> Date? {
        let teile = tag.split(separator: "-").compactMap { Int($0) }
        guard teile.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: teile[0], month: teile[1], day: teile[2], hour: 12))
    }

    /// Bereich der Gewichtsachse: etwas Luft über und unter den Werten, nie bei 0 beginnend.
    var achse: ClosedRange<Double>? {
        let werte = tage.compactMap(\.kg) + tage.compactMap(\.mittel)
        guard let unten = werte.min(), let oben = werte.max() else { return nil }
        return (unten - 1).rounded(.down)...(oben + 1).rounded(.up)
    }
}

enum Gewichtstext {
    static func kg(_ wert: Double) -> String {
        String(format: "%.1f kg", wert).replacingOccurrences(of: ".", with: ",")
    }

    static func proWoche(_ wert: Double) -> String {
        let betrag = String(format: "%.2f", abs(wert)).replacingOccurrences(of: ".", with: ",")
        if abs(wert) < 0.005 { return "unverändert" }
        return "\(wert < 0 ? "−" : "+")\(betrag) kg je Woche"
    }
}

extension Color {
    /// Bereichsfarbe „gesundheit“ aus dem Designkonzept, hell und dunkel.
    static let gesundheit = Color(uiColor: UIColor { merkmale in
        merkmale.userInterfaceStyle == .dark
            ? UIColor(red: 0xD9 / 255, green: 0x51 / 255, blue: 0x8D / 255, alpha: 1)
            : UIColor(red: 0xA7 / 255, green: 0x13 / 255, blue: 0x45 / 255, alpha: 1)
    })
}

/// Körpergewicht eintragen und den Verlauf ansehen. Geht nie an Claude.
struct GewichtView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var verlauf: Gewichtsverlauf?
    @State private var standVon: Date?
    @State private var fehler: String?
    @State private var traegtEin = false

    var body: some View {
        List {
            if let fehler, verlauf != nil {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                }
            }
            if let verlauf {
                if verlauf.messungen.isEmpty && verlauf.letzte == nil {
                    Section {
                        Text("Noch keine Messung. Trag dein Gewicht ein, dann entsteht hier der Verlauf.")
                            .foregroundStyle(Color.secondary)
                    }
                } else {
                    uebersicht(verlauf)
                    diagramm(verlauf)
                    messungen(verlauf)
                }
            } else if let fehler {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.orange)
                }
            } else {
                Section { ProgressView() }
            }
            let wartend = schlange.eintraege.filter { $0.art == .gewicht }
            if !wartend.isEmpty {
                Section {
                    ForEach(wartend) { eintrag in
                        Label(eintrag.titel, systemImage: "clock")
                            .foregroundStyle(Color.secondary)
                    }
                } footer: {
                    Text("Wird gesendet, sobald dein Server erreichbar ist.")
                }
            }
        }
        .navigationTitle("Gewicht")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    traegtEin = true
                } label: {
                    Label("Eintragen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $traegtEin) {
            GewichtBlatt(vorschlag: verlauf?.letzte?.kg)
        }
        .refreshable { await laden() }
        .task { await laden() }
        .onChange(of: schlange.neuesAmServer) {
            Task { await laden() }
        }
    }

    private func uebersicht(_ verlauf: Gewichtsverlauf) -> some View {
        Section {
            if let letzte = verlauf.letzte {
                LabeledContent("Zuletzt", value: Gewichtstext.kg(letzte.kg))
            }
            if let mittel = verlauf.tage.last?.mittel {
                LabeledContent("Mittel über 7 Tage", value: Gewichtstext.kg(mittel))
            }
            if let proWoche = verlauf.veraenderung?.kgProWoche {
                LabeledContent("Letzte 4 Wochen", value: Gewichtstext.proWoche(proWoche))
            } else if let grund = verlauf.veraenderung?.grund {
                Text(grund)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        } footer: {
            if let standVon {
                Text("Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
    }

    private func diagramm(_ verlauf: Gewichtsverlauf) -> some View {
        Section {
            Chart {
                ForEach(verlauf.tage) { tag in
                    if let datum = Gewichtsverlauf.datum(tag.tag), let mittel = tag.mittel {
                        LineMark(x: .value("Tag", datum), y: .value("Mittel über 7 Tage", mittel))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(Color.gesundheit)
                    }
                }
                ForEach(verlauf.tage) { tag in
                    if let datum = Gewichtsverlauf.datum(tag.tag), let kg = tag.kg {
                        PointMark(x: .value("Tag", datum), y: .value("Messung", kg))
                            .symbolSize(40)
                            .foregroundStyle(Color.gesundheit.opacity(0.45))
                    }
                }
            }
            .chartYScale(domain: verlauf.achse ?? 0...100)
            .chartYAxisLabel("kg")
            .frame(height: 220)
            .padding(.vertical, 4)
            .accessibilityLabel("Verlauf des Gewichts über 90 Tage")
        } header: {
            Text("Letzte 90 Tage")
        } footer: {
            Text("Punkte sind einzelne Messungen, die Linie ist das Mittel über 7 Tage. Das Gewicht schwankt von Tag zu Tag um 1 bis 2 kg, deshalb sagt die Linie mehr als ein einzelner Punkt.")
        }
    }

    private func messungen(_ verlauf: Gewichtsverlauf) -> some View {
        Section {
            ForEach(verlauf.messungen.reversed()) { messung in
                LabeledContent(tagText(messung.tag), value: Gewichtstext.kg(messung.kg))
                    .swipeActions(edge: .trailing) {
                        Button("Löschen", role: .destructive) {
                            Task { await loeschen(messung) }
                        }
                    }
            }
        } header: {
            Text("Messungen")
        } footer: {
            Text("Zum Löschen nach links wischen.")
        }
    }

    private func tagText(_ tag: String?) -> String {
        guard let tag, let datum = Gewichtsverlauf.datum(tag) else { return tag ?? "" }
        return datum.formatted(date: .abbreviated, time: .omitted)
    }

    private func laden() async {
        do {
            let neu = try await zustand.api().lesen(Gewichtsverlauf.self, "GET", "/api/koerper/gewicht/verlauf?tage=90")
            verlauf = neu
            standVon = nil
            fehler = nil
            schlange.merken(neu, als: "gewicht")
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Gewichtsverlauf.self, "gewicht") {
                verlauf = alt
                standVon = wann
            } else {
                fehler = Api.text(error)
            }
        }
    }

    private func loeschen(_ messung: Gewichtsverlauf.Messung) async {
        do {
            _ = try await zustand.api().daten("DELETE", "/api/koerper/gewicht/\(messung.id)")
            await laden()
        } catch {
            fehler = "Löschen geht nur, wenn der Server erreichbar ist: \(Api.text(error))"
        }
    }
}

/// Eine Messung eintragen. Sie geht über die Warteschlange, also auch unterwegs.
struct GewichtBlatt: View {
    let vorschlag: Double?
    @Environment(\.dismiss) private var schliessen
    @State private var kg = ""
    @State private var zeit = Date()
    @State private var fehler: String?
    @FocusState private var tippt: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(vorschlag.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "z. B. 82,4",
                              text: $kg)
                        .keyboardType(.decimalPad)
                        .focused($tippt)
                    DatePicker("Gemessen", selection: $zeit, in: ...Date())
                } header: {
                    Text("Gewicht in kg")
                } footer: {
                    Text("Bleibt auf deinem Server und geht nie an Claude.")
                }
                if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            .navigationTitle("Gewicht eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { speichern() }
                }
            }
            .onAppear { tippt = true }
        }
    }

    private func speichern() {
        // Dieselben Grenzen wie am Server, damit der Eintrag nicht erst dort scheitert.
        guard let wert = Zahl.lesen(kg), wert >= 20, wert <= 350 else {
            fehler = "Bitte ein Gewicht zwischen 20 und 350 kg eingeben."
            return
        }
        let eintrag = Eintrag(id: Eintrag.neueKennung(), art: .gewicht, zeit: zeit,
                              titel: "Gewicht \(Gewichtstext.kg(wert))", kg: wert)
        do {
            try Warteschlange.shared.aufnehmen(eintrag)
            Task { await Warteschlange.shared.senden() }
            schliessen()
        } catch {
            fehler = error.localizedDescription
        }
    }
}
