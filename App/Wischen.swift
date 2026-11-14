import SwiftUI

/// Wechsel zwischen den Tabs durch Wischen nach links und rechts. Die Regeln stehen ohne Oberfläche, damit sie sich testen lassen.
enum Wischen {
    /// So weit muss der Finger waagerecht gewandert sein.
    static let mindestweg: CGFloat = 70
    /// Die Bewegung muss deutlich waagerechter als senkrecht sein, sonst ist es Scrollen.
    static let verhaeltnis: CGFloat = 2.5

    /// +1: zum nächsten Tab (nach links gewischt), −1: zum vorigen (nach rechts gewischt), 0: kein Tab-Wechsel.
    static func richtung(waagerecht: CGFloat, senkrecht: CGFloat) -> Int {
        guard abs(waagerecht) >= mindestweg, abs(waagerecht) >= verhaeltnis * abs(senkrecht) else { return 0 }
        return waagerecht < 0 ? 1 : -1
    }

    /// Der Tab nach dem Wischen. Am Rand bleibt es beim ersten bzw. letzten.
    static func ziel(aktuell: Int, richtung: Int, anzahl: Int) -> Int {
        min(max(aktuell + richtung, 0), max(anzahl - 1, 0))
    }
}

private struct TabWechselKey: EnvironmentKey {
    static let defaultValue: (Int) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Wechselt um einen Tab weiter (+1) oder zurück (−1). Gesetzt vom Hauptbildschirm.
    var tabWechsel: (Int) -> Void {
        get { self[TabWechselKey.self] }
        set { self[TabWechselKey.self] = newValue }
    }
}

private struct TabWischen: ViewModifier {
    @Environment(\.tabWechsel) private var tabWechsel

    func body(content: Content) -> some View {
        // Gleichzeitig mit dem Scrollen der Liste, nicht an dessen Stelle.
        content.simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { geste in
                    let richtung = Wischen.richtung(waagerecht: geste.translation.width, senkrecht: geste.translation.height)
                    if richtung != 0 { tabWechsel(richtung) }
                }
        )
    }
}

extension View {
    /// Für den obersten Bildschirm eines Tabs. Auf Unterseiten bleibt Wischen vom Rand das Zurückgehen.
    func wischtZwischenTabs() -> some View {
        modifier(TabWischen())
    }
}
