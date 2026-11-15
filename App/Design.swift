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
