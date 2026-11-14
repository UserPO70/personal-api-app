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
}

/// Der Tag auf einen Blick: Essen mit Ziel, Bewegung, Schlaf, PC-Zeit, Gewicht.
struct HeuteView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var tag: Tagesueberblick?
    @State private var standVon: Date?
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            List {
                if zustand.demo {
                    Section {
                        Label("Demo: ausgedachte Daten, kein Server", systemImage: "theatermasks")
                            .foregroundStyle(Color.secondary)
                    }
                }
                if let tag {
                    essen(tag)
                    bewegung(tag)
                    if let minuten = tag.uebersicht?.schlaf?.minuten {
                        Section("Schlaf") {
                            LabeledContent("Letzte Nacht", value: Dauertext.minuten(minuten))
                        }
                    }
                    if let minuten = tag.uebersicht?.pcMinuten, minuten > 0 {
                        Section("PC-Zeit") {
                            LabeledContent("Heute", value: Dauertext.minuten(minuten))
                        }
                    }
                    if !zustand.demo {
                        Section {
                            NavigationLink {
                                KalorienView()
                            } label: {
                                LabeledContent("Gewicht und Ziel", value: tag.koerper?.gewicht.map { Gewichtstext.kg($0.kg) } ?? "eintragen")
                            }
                        }
                    }
                } else if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.orange)
                    }
                } else {
                    Section { ProgressView() }
                }
            }
            .navigationTitle("Heute")
            .refreshable { await laden() }
            .task { await laden() }
            .onChange(of: schlange.neuesAmServer) {
                Task { await laden() }
            }
        }
    }

    private func essen(_ tag: Tagesueberblick) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(Zahl.kcal(tag.essen?.summe?.kcal))
                    .font(.title2.bold())
                if let ziel = tag.essen?.ziel {
                    ProgressView(value: Kalorientext.anteil(gegessen: tag.essen?.summe?.kcal, ziel: ziel.kcal))
                        .tint(Color.essen)
                    Text("Ziel \(Zahl.kcal(ziel.kcal)) · \(Kalorientext.offen(gegessen: tag.essen?.summe?.kcal, ziel: ziel.kcal))")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                } else if (tag.essen?.anzahl ?? 0) == 0 {
                    Text("Heute ist noch nichts eingetragen.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Essen")
        } footer: {
            if let standVon {
                Text("Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
    }

    @ViewBuilder
    private func bewegung(_ tag: Tagesueberblick) -> some View {
        let uebersicht = tag.uebersicht
        if uebersicht?.schritte != nil || uebersicht?.strecke != nil || uebersicht?.stockwerke != nil {
            Section("Bewegung") {
                if let schritte = uebersicht?.schritte {
                    LabeledContent("Schritte", value: Dauertext.ganzzahl(schritte))
                }
                if let strecke = uebersicht?.strecke {
                    LabeledContent("Strecke", value: Dauertext.kilometer(strecke))
                }
                if let stockwerke = uebersicht?.stockwerke {
                    LabeledContent("Stockwerke", value: Dauertext.ganzzahl(stockwerke))
                }
            }
        }
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
                    .foregroundStyle(Color.orange)
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
