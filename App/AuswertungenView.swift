import Charts
import SwiftUI

/// Der Tab „Auswertungen“: Gesundheit und PC-Zeit im Verlauf. Jede Zeile führt zur Kennzahl mit Diagramm.
struct AuswertungenView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var verlauf: Tagesverlauf?
    @State private var standVon: Date?
    @State private var fehler: String?

    private static let tage = 30

    var body: some View {
        NavigationStack {
            AppListe {
                if zustand.demo {
                    Section {
                        Label("Demo: ausgedachte Daten, kein Server", systemImage: "theatermasks")
                            .foregroundStyle(Color.text2)
                    }
                }
                if let verlauf {
                    let gesundheit = Kennzahl.gesundheit.filter { verlauf.schnitt($0) != nil }
                    if !gesundheit.isEmpty {
                        Section("Gesundheit") {
                            ForEach(gesundheit) { kennzahl in
                                zeile(kennzahl, verlauf)
                            }
                        }
                    }
                    if verlauf.schnitt(.pcZeit) != nil {
                        Section("PC-Zeit") {
                            zeile(.pcZeit, verlauf)
                        }
                    }
                    if gesundheit.isEmpty && verlauf.schnitt(.pcZeit) == nil {
                        Section {
                            Text("In den letzten \(Self.tage) Tagen gibt es keine Daten zu Gesundheit oder PC-Zeit.")
                                .foregroundStyle(Color.text2)
                        }
                    } else {
                        Section {
                        } footer: {
                            Text(fusszeile)
                        }
                    }
                } else if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.warnung)
                    }
                } else {
                    Section { ProgressView() }
                }
            }
            .navigationTitle("Auswertungen")
            .refreshable { await laden() }
            .task { await laden() }
        }
    }

    private var fusszeile: String {
        var text = "Durchschnitt der letzten \(Self.tage) Tage, gerechnet nur über Tage mit Daten."
        if let standVon {
            text += " Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }

    private func zeile(_ kennzahl: Kennzahl, _ verlauf: Tagesverlauf) -> some View {
        NavigationLink {
            KennzahlView(kennzahl: kennzahl)
                .alsUnterseite()
        } label: {
            HStack(spacing: Abstand.kachel) {
                Image(systemName: kennzahl.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(kennzahl.farbe)
                    .frame(width: 28)
                Text(kennzahl.name)
                Spacer(minLength: Abstand.eng)
                if let schnitt = verlauf.schnitt(kennzahl) {
                    Text("Ø \(kennzahl.text(schnitt.wert))")
                        .monospacedDigit()
                        .foregroundStyle(Color.text2)
                }
            }
        }
    }

    private func laden() async {
        if zustand.demo {
            verlauf = Tagesverlauf.demo(tage: Self.tage)
            return
        }
        do {
            let neu = try await zustand.api().lesen(Tagesverlauf.self, "GET", "/api/dashboard/verlauf?tage=\(Self.tage)")
            verlauf = neu
            standVon = nil
            fehler = nil
            schlange.merken(neu, als: "verlauf-\(Self.tage)")
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Tagesverlauf.self, "verlauf-\(Self.tage)") {
                verlauf = alt
                standVon = wann
            } else {
                fehler = Api.text(error)
            }
        }
    }
}

/// Eine Kennzahl im Verlauf: ein Satz dazu, Säulen je Tag und die Linie über 7 Tage. Bei der PC-Zeit auch,
/// womit und an welchen Rechnern.
struct KennzahlView: View {
    let kennzahl: Kennzahl

    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var tage = 30
    @State private var verlauf: Tagesverlauf?
    @State private var pc: PcKategorien?
    @State private var standVon: Date?
    @State private var fehler: String?
    @State private var gewaehlt: Date?

    var body: some View {
        AppListe {
            Section {
                Picker("Zeitraum", selection: $tage) {
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                    Text("1 Jahr").tag(365)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let verlauf {
                diagramm(verlauf)
                if kennzahl == .pcZeit, let pc {
                    pcTeile(pc)
                }
            } else if let fehler {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warnung)
                }
            } else {
                Section { ProgressView() }
            }
        }
        .navigationTitle(kennzahl.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await laden() }
        .task(id: tage) { await laden() }
    }

    // MARK: Diagramm

    @ViewBuilder
    private func diagramm(_ verlauf: Tagesverlauf) -> some View {
        Section {
            if let schnitt = verlauf.schnitt(kennzahl) {
                Text(verlauf.trend(kennzahl)?.vergleich?.text ?? kennzahl.schnittText(schnitt))
                    .font(.subheadline)
                Chart {
                    ForEach(verlauf.tage) { tag in
                        if let datum = Gewichtsverlauf.datum(tag.tag), let wert = kennzahl.wert(tag) {
                            if kennzahl.jeTag {
                                BarMark(x: .value("Tag", datum, unit: .day), y: .value(kennzahl.name, kennzahl.imDiagramm(wert)))
                                    .foregroundStyle(kennzahl.farbe.opacity(0.35))
                                    .cornerRadius(tage > 90 ? 0 : 3)
                            } else {
                                // Tempo und Schrittlänge schwanken nur wenig: Punkte auf einer Achse nah an den Werten.
                                PointMark(x: .value("Tag", datum, unit: .day), y: .value(kennzahl.name, kennzahl.imDiagramm(wert)))
                                    .symbolSize(tage > 90 ? 12 : 30)
                                    .foregroundStyle(kennzahl.farbe.opacity(0.45))
                            }
                        }
                    }
                    ForEach(verlauf.linie(kennzahl)) { punkt in
                        if let datum = Gewichtsverlauf.datum(punkt.tag) {
                            LineMark(x: .value("Tag", datum, unit: .day),
                                     y: .value("Mittel über 7 Tage", kennzahl.imDiagramm(punkt.wert)),
                                     series: .value("Stück", punkt.stueck))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .foregroundStyle(kennzahl.farbe)
                        }
                    }
                    if let gewaehlt {
                        RuleMark(x: .value("Tag", gewaehlt, unit: .day))
                            .foregroundStyle(Color.text3)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXSelection(value: $gewaehlt)
                .chartYScale(domain: verlauf.achse(kennzahl))
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4))
                }
                .chartYAxisLabel(kennzahl.achse)
                .frame(height: 220)
                .padding(.vertical, Abstand.winzig)
                .accessibilityLabel("\(kennzahl.name) je Tag, letzte \(tage) Tage")
                LabeledContent(gewaehlt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Tag antippen",
                               value: gewaehlt.map { wertText(am: $0, verlauf) } ?? "")
                    .font(.subheadline)
                    .foregroundStyle(gewaehlt == nil ? Color.text2 : Color.text)
            } else {
                Text("In den letzten \(tage) Tagen gibt es dazu keine Daten.")
                    .foregroundStyle(Color.text2)
            }
        } footer: {
            Text(fusszeile(verlauf))
        }
    }

    private func fusszeile(_ verlauf: Tagesverlauf) -> String {
        var text = kennzahl.jeTag ? "Säulen sind einzelne Tage" : "Punkte sind einzelne Tage"
        text += verlauf.linie(kennzahl).isEmpty ? "." : ", die Linie ist das Mittel über 7 Tage."
        text += " Tage ohne Daten bleiben leer und zählen nicht als 0."
        if let standVon {
            text += " Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }

    /// Der Wert des angetippten Tages, oder dass es keinen gibt.
    private func wertText(am datum: Date, _ verlauf: Tagesverlauf) -> String {
        let kalender = Calendar.current
        let tag = verlauf.tage.first { eintrag in
            Gewichtsverlauf.datum(eintrag.tag).map { kalender.isDate($0, inSameDayAs: datum) } ?? false
        }
        guard let tag, let wert = kennzahl.wert(tag) else { return "keine Daten" }
        return kennzahl.text(wert)
    }

    // MARK: PC-Zeit

    @ViewBuilder
    private func pcTeile(_ pc: PcKategorien) -> some View {
        if !pc.kategorien.isEmpty {
            Section("Womit") {
                ForEach(pc.kategorien) { kategorie in
                    LabeledContent {
                        Text(Dauertext.minuten(kategorie.minuten))
                            .monospacedDigit()
                    } label: {
                        Text(kategorie.name)
                        if let anteil = kategorie.anteil {
                            Text("\(Int(anteil.rounded())) %")
                        }
                    }
                }
            }
        }
        if pc.geraete.count > 1 {
            Section("Rechner") {
                ForEach(pc.geraete) { geraet in
                    LabeledContent {
                        Text(Dauertext.minuten(geraet.minuten))
                            .monospacedDigit()
                    } label: {
                        Text(geraet.name)
                    }
                }
            }
        }
        if !pc.spiele.isEmpty {
            Section("Spiele") {
                ForEach(pc.spiele) { spiel in
                    LabeledContent {
                        Text(Dauertext.minuten(spiel.minuten))
                            .monospacedDigit()
                    } label: {
                        Text(spiel.name)
                        if let tage = spiel.tage {
                            Text(tage == 1 ? "an 1 Tag" : "an \(tage) Tagen")
                        }
                    }
                }
            }
        }
    }

    // MARK: Laden

    private func laden() async {
        gewaehlt = nil
        if zustand.demo {
            verlauf = Tagesverlauf.demo(tage: tage)
            pc = kennzahl == .pcZeit ? PcKategorien.demo : nil
            return
        }
        let merkname = "verlauf-\(tage)"
        do {
            let neu = try await zustand.api().lesen(Tagesverlauf.self, "GET", "/api/dashboard/verlauf?tage=\(tage)")
            verlauf = neu
            standVon = nil
            fehler = nil
            schlange.merken(neu, als: merkname)
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Tagesverlauf.self, merkname) {
                verlauf = alt
                standVon = wann
            } else {
                verlauf = nil
                fehler = Api.text(error)
            }
        }
        guard kennzahl == .pcZeit else { return }
        do {
            let neu = try await zustand.api().lesen(PcKategorien.self, "GET", "/api/pc/kategorien?tage=\(tage)")
            pc = neu
            schlange.merken(neu, als: "pc-\(tage)")
        } catch {
            if Task.isCancelled { return }
            pc = schlange.gemerkt(PcKategorien.self, "pc-\(tage)")?.0
        }
    }
}
