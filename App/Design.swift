import SwiftUI

/// Die gemeinsame Design-Grundlage: Farben, Abstände, Ecken und die Bausteine, die jeder Bildschirm nutzt.
/// Vorlage ist das Designkonzept (APP-DESIGN.md im Server-Projekt). Feste Farbwerte und Maße stehen nur hier
/// und in den Farbsätzen (Assets.xcassets), nie in einem Bildschirm.
enum Farbe: String, CaseIterable {
    case grund = "FarbeGrund"
    case flaeche = "FarbeFlaeche"
    case flaeche2 = "FarbeFlaeche2"
    case rand = "FarbeRand"
    case text = "FarbeText"
    case text2 = "FarbeText2"
    case text3 = "FarbeText3"
    case aufAkzent = "FarbeAufAkzent"
    case essen = "FarbeEssen"
    case orte = "FarbeOrte"
    case gesundheit = "FarbeGesundheit"
    case pcZeit = "FarbePcZeit"
    case wetter = "FarbeWetter"
    case ok = "FarbeOk"
    case warnung = "FarbeWarnung"
    case fehler = "FarbeFehler"

    var farbe: Color { Color(rawValue) }
}

extension Color {
    // Flächen und Text
    /// Hintergrund des Bildschirms.
    static let grund = Farbe.grund.farbe
    /// Karten, Kacheln, Listenzeilen.
    static let flaeche = Farbe.flaeche.farbe
    /// Blasse Flächen ohne Aussage.
    static let flaeche2 = Farbe.flaeche2.farbe
    /// Trennlinien, Diagramm-Raster.
    static let rand = Farbe.rand.farbe
    /// Werte, Titel, Fließtext.
    static let text = Farbe.text.farbe
    /// Namen, Untertitel, Hinweise.
    static let text2 = Farbe.text2.farbe
    /// Gedämpft.
    static let text3 = Farbe.text3.farbe
    /// Text auf der gefärbten Hauptaktion.
    static let aufAkzent = Farbe.aufAkzent.farbe

    // Bereiche: Die Farbe sitzt im Symbol oder in der Fläche, nie im Text.
    static let essen = Farbe.essen.farbe
    static let orte = Farbe.orte.farbe
    static let gesundheit = Farbe.gesundheit.farbe
    static let pcZeit = Farbe.pcZeit.farbe
    static let wetter = Farbe.wetter.farbe

    // Zustände: immer mit Symbol und Text.
    static let ok = Farbe.ok.farbe
    /// Aufpassen.
    static let warnung = Farbe.warnung.farbe
    /// Etwas braucht dich.
    static let fehler = Farbe.fehler.farbe
}

/// Hell, dunkel oder wie das iPhone: der Schalter in den Einstellungen.
enum Darstellung: String, CaseIterable, Identifiable {
    case system, hell, dunkel

    static let schluessel = "darstellung"

    static var gespeichert: Darstellung {
        UserDefaults.standard.string(forKey: schluessel).flatMap(Darstellung.init(rawValue:)) ?? .system
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "System"
        case .hell: return "Hell"
        case .dunkel: return "Dunkel"
        }
    }

    var stil: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .hell: return .light
        case .dunkel: return .dark
        }
    }

    /// Gilt für alle Fenster der App, also auch für Blätter und die Kamera-Ansicht.
    @MainActor
    func anwenden() {
        for szene in UIApplication.shared.connectedScenes {
            for fenster in (szene as? UIWindowScene)?.windows ?? [] {
                fenster.overrideUserInterfaceStyle = stil
            }
        }
    }
}

/// Abstände in Punkten.
enum Abstand {
    /// Symbol und Text, Wert und Einheit.
    static let winzig: CGFloat = 4
    /// Innerhalb einer Gruppe.
    static let eng: CGFloat = 8
    /// Zwischen Kacheln.
    static let kachel: CGFloat = 12
    /// Innenrand einer Karte, Rand des Bildschirms.
    static let rand: CGFloat = 16
    /// Zwischen Abschnitten.
    static let abschnitt: CGFloat = 24
    /// Vor einem neuen großen Bereich.
    static let bereich: CGFloat = 32
}

/// Eckenradien in Punkten. Knöpfe sind Kapseln und brauchen keinen.
enum Ecke {
    /// Vorschaubild in einer Listenzeile.
    static let bild: CGFloat = 8
    /// Eingabefeld, kleine Fläche.
    static let feld: CGFloat = 12
    static let kachel: CGFloat = 16
    /// Große Karte.
    static let karte: CGFloat = 20
}

extension View {
    /// Eine Fläche auf dem Grund: Karte oder Kachel. Ohne Schatten, sie hebt sich nur durch die Farbe ab.
    func alsFlaeche(innen: CGFloat = Abstand.rand, ecke: CGFloat = Ecke.kachel) -> some View {
        padding(innen)
            .background(Color.flaeche, in: RoundedRectangle(cornerRadius: ecke))
    }
}

/// Eine Systemliste in den Farben der App: Grund dahinter, Zeilen als Fläche.
struct AppListe<Inhalt: View>: View {
    @ViewBuilder let inhalt: () -> Inhalt

    var body: some View {
        List {
            Group(content: inhalt)
                .listRowBackground(Color.flaeche)
        }
        .scrollContentBackground(.hidden)
        .background(Color.grund)
    }
}

/// Ein Formular in den Farben der App.
struct AppFormular<Inhalt: View>: View {
    @ViewBuilder let inhalt: () -> Inhalt

    var body: some View {
        Form {
            Group(content: inhalt)
                .listRowBackground(Color.flaeche)
        }
        .scrollContentBackground(.hidden)
        .background(Color.grund)
    }
}

/// Ein Kalendertag als Text, wie der Server ihn will: `2026-03-14`.
enum Kalendertag {
    static func heute(jetzt: Date = Date(), kalender: Calendar = .current) -> String {
        let teile = kalender.dateComponents([.year, .month, .day], from: jetzt)
        return String(format: "%04d-%02d-%02d", teile.year ?? 0, teile.month ?? 0, teile.day ?? 0)
    }

    static func verschoben(_ tag: String, um tage: Int, kalender: Calendar = .current) -> String {
        guard let datum = Gewichtsverlauf.datum(tag),
              let neu = kalender.date(byAdding: .day, value: tage, to: datum) else { return tag }
        return heute(jetzt: neu, kalender: kalender)
    }

    /// „Heute“, „Gestern“ oder „Mo., 16. Nov.“. `heute` ist der laufende Tag des Bereichs (beim Essen bis 4 Uhr früh
    /// noch der Vortag).
    static func name(_ tag: String, heute: String) -> String {
        if tag == heute { return "Heute" }
        if tag == verschoben(heute, um: -1) { return "Gestern" }
        guard let datum = Gewichtsverlauf.datum(tag) else { return tag }
        return datum.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// Tag zurück, Name des Tages, Tag vor: oben in „Essen“ und „Orte“. In die Zukunft geht es nicht.
struct TagWahl: View {
    @Binding var tag: String
    let heute: String

    var body: some View {
        HStack(spacing: Abstand.eng) {
            Button {
                tag = Kalendertag.verschoben(tag, um: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Tag davor")
            Spacer(minLength: 0)
            Text(Kalendertag.name(tag, heute: heute))
                .font(.headline)
                .monospacedDigit()
            Spacer(minLength: 0)
            Button {
                tag = Kalendertag.verschoben(tag, um: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(tag >= heute)
            .accessibilityLabel("Tag danach")
        }
        .buttonStyle(.borderless)
        .alsFlaeche(innen: Abstand.winzig, ecke: Ecke.feld)
    }
}
