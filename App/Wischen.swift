import SwiftUI

/// Die Tabs der App. Zwischen ihnen wird gewischt: Der Nachbar gleitet mit dem Finger herein.
enum Reiter: Int, CaseIterable, Identifiable {
    case heute, essen, orte, auswertungen, einstellungen

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .heute: return "Heute"
        case .essen: return "Essen"
        case .orte: return "Orte"
        case .auswertungen: return "Auswertungen"
        case .einstellungen: return "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .heute: return "sun.max"
        case .essen: return "fork.knife"
        case .orte: return "map"
        case .auswertungen: return "chart.xyaxis.line"
        case .einstellungen: return "gearshape"
        }
    }
}

/// Merkt sich, ob gerade eine Unterseite offen ist. Dann wird nicht zwischen den Tabs gewischt,
/// damit Wischen vom Rand das Zurückgehen bleibt, und die Tab-Leiste macht Platz.
@MainActor
final class Seitenlage: ObservableObject {
    @Published private(set) var tiefe = 0

    var aufUnterseite: Bool { tiefe > 0 }

    func betreten() {
        tiefe += 1
    }

    func verlassen() {
        tiefe = max(tiefe - 1, 0)
    }
}

private struct Unterseite: ViewModifier {
    @EnvironmentObject private var lage: Seitenlage

    func body(content: Content) -> some View {
        content
            .onAppear { lage.betreten() }
            .onDisappear { lage.verlassen() }
    }
}

extension View {
    /// Für jeden Bildschirm, der über einen Tab geschoben wird (Details, Gewicht und Ziel, …).
    func alsUnterseite() -> some View {
        modifier(Unterseite())
    }
}

/// Wo die Seiten gerade stehen, als Kommazahl: 1,5 heißt halb zwischen Essen und Orte. Folgt beim Wischen dem Finger,
/// damit die Markierung in der Leiste mitgleitet. Eigenes Objekt, damit nur die Leiste bei jeder Bewegung neu zeichnet.
@MainActor
final class Blaetterstand: ObservableObject {
    @Published var stelle: CGFloat = 0

    /// Neue Stelle aus dem Wischen. Sprünge um mehr als eine halbe Seite kommen nur vom Zurücksetzen der Blätter-Ansicht
    /// am Ende einer Bewegung, nie vom Finger, und werden übergangen.
    func gewischt(_ neu: CGFloat, anzahl: Int) {
        let begrenzt = min(max(neu, 0), CGFloat(anzahl - 1))
        guard abs(begrenzt - stelle) <= 0.5 else { return }
        stelle = begrenzt
    }
}

/// Die Leiste unten. Eine eigene statt der von iOS, weil nur so die Tabs mit dem Finger mitgleiten können.
struct Tableiste: View {
    /// So viel Platz hält jede Seite unten für die Leiste frei.
    static let hoehe: CGFloat = 64

    @Binding var tab: Reiter
    @ObservedObject var stand: Blaetterstand

    private static let abstand: CGFloat = 2

    /// Der Tab, über dem die Markierung gerade am meisten steht: Er bekommt Farbe und volles Symbol.
    private var hervorgehoben: Reiter {
        Reiter(rawValue: Int(stand.stelle.rounded())) ?? tab
    }

    var body: some View {
        HStack(spacing: Self.abstand) {
            ForEach(Reiter.allCases) { eintrag in
                Button {
                    withAnimation(.snappy) {
                        tab = eintrag
                        stand.stelle = CGFloat(eintrag.rawValue)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: eintrag.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .symbolVariant(hervorgehoben == eintrag ? .fill : .none)
                            .frame(height: 24)
                        Text(eintrag.name)
                            // Feste Größe wie in der Tab-Leiste von iOS, damit alle Namen gleich groß bleiben.
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(hervorgehoben == eintrag ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(eintrag.name)
                .accessibilityAddTraits(tab == eintrag ? .isSelected : [])
            }
        }
        // Die Markierung liegt unter den Knöpfen und gleitet mit der Stelle der Seiten.
        .background(alignment: .leading) {
            GeometryReader { flaeche in
                let anzahl = CGFloat(Reiter.allCases.count)
                let breite = (flaeche.size.width - Self.abstand * (anzahl - 1)) / anzahl
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: breite, height: flaeche.size.height)
                    .offset(x: stand.stelle * (breite + Self.abstand))
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 2)
        .padding(.horizontal, Abstand.kachel)
        .padding(.bottom, 2)
    }
}

/// Die Tabs als Seiten nebeneinander, mit dem Blättern von iOS (UIPageViewController): Der Nachbar gleitet mit dem
/// Finger herein. Jede Seite ist ein eigener, dauerhaft gehaltener Bildschirm, damit beim Blättern nichts verloren geht.
struct Seiten: UIViewControllerRepresentable {
    @Binding var tab: Reiter
    /// Auf einer Unterseite wird nicht geblättert.
    let gesperrt: Bool
    /// Platz für die Tab-Leiste am unteren Rand jeder Seite.
    let platzUnten: CGFloat
    /// Die Bildschirme in der Reihenfolge der Tabs. Nur beim Anlegen gelesen.
    let seiten: [AnyView]
    /// Bekommt beim Wischen laufend die Stelle, für die Markierung in der Leiste.
    let stand: Blaetterstand

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: $tab, bildschirme: seiten.map { UIHostingController(rootView: $0) }, stand: stand)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let blaetterer = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        blaetterer.dataSource = context.coordinator
        blaetterer.delegate = context.coordinator
        blaetterer.view.backgroundColor = UIColor(named: Farbe.grund.rawValue)
        let bildschirme = context.coordinator.bildschirme
        if bildschirme.indices.contains(tab.rawValue) {
            blaetterer.setViewControllers([bildschirme[tab.rawValue]], direction: .forward, animated: false)
        }
        stand.stelle = CGFloat(tab.rawValue)
        context.coordinator.beobachten(blaetterer)
        return blaetterer
    }

    func updateUIViewController(_ blaetterer: UIPageViewController, context: Context) {
        let koordinator = context.coordinator
        koordinator.tab = $tab
        // Nur das seitliche Blättern sperren, nicht das Scrollen der Seiten selbst.
        for ansicht in blaetterer.view.subviews {
            (ansicht as? UIScrollView)?.isScrollEnabled = !gesperrt
        }
        for bildschirm in koordinator.bildschirme {
            bildschirm.additionalSafeAreaInsets.bottom = platzUnten
        }
        // Tab über die Leiste gewählt: dorthin gleiten.
        guard let sichtbar = blaetterer.viewControllers?.first,
              let stelle = koordinator.bildschirme.firstIndex(of: sichtbar),
              stelle != tab.rawValue, koordinator.bildschirme.indices.contains(tab.rawValue) else { return }
        // Die Leiste gleitet dabei selbst (Tableiste); das Mitlesen der Bewegung ruht so lange.
        koordinator.programmatisch = true
        blaetterer.setViewControllers([koordinator.bildschirme[tab.rawValue]],
                                      direction: tab.rawValue > stelle ? .forward : .reverse, animated: true) { _ in
            koordinator.programmatisch = false
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var tab: Binding<Reiter>
        let bildschirme: [UIViewController]
        let stand: Blaetterstand
        private var beobachtung: NSKeyValueObservation?
        /// Wahr, solange die Seiten nach einem Tipp auf die Leiste gleiten (nicht nach dem Finger).
        var programmatisch = false

        init(tab: Binding<Reiter>, bildschirme: [UIViewController], stand: Blaetterstand) {
            self.tab = tab
            self.bildschirme = bildschirme
            self.stand = stand
        }

        /// Liest beim Wischen mit, wie weit die Seiten verschoben sind. Der Delegate der Scroll-Ansicht gehört der
        /// Blätter-Ansicht selbst, deshalb über Key-Value-Observing statt als Delegate.
        @MainActor
        func beobachten(_ blaetterer: UIPageViewController) {
            guard let rollen = blaetterer.view.subviews.compactMap({ $0 as? UIScrollView }).first else { return }
            beobachtung = rollen.observe(\.contentOffset, options: [.new]) { [weak self, weak blaetterer] rollen, _ in
                MainActor.assumeIsolated {
                    // Jede Bewegung zählt, auch das Weitergleiten nach dem Loslassen: Das fährt iOS als eigene
                    // Animation, nicht als Ausrollen. Bezug ist der Tab, auf dem das Wischen begann; er wechselt
                    // erst, wenn die neue Seite ganz da ist.
                    guard let self, blaetterer != nil, !self.programmatisch, rollen.bounds.width > 0 else { return }
                    let versatz = (rollen.contentOffset.x - rollen.bounds.width) / rollen.bounds.width
                    self.stand.gewischt(CGFloat(self.tab.wrappedValue.rawValue) + versatz, anzahl: self.bildschirme.count)
                }
            }
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let stelle = bildschirme.firstIndex(of: viewController), stelle > 0 else { return nil }
            return bildschirme[stelle - 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let stelle = bildschirme.firstIndex(of: viewController), stelle + 1 < bildschirme.count else { return nil }
            return bildschirme[stelle + 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let sichtbar = pageViewController.viewControllers?.first,
                  let stelle = bildschirme.firstIndex(of: sichtbar), let neu = Reiter(rawValue: stelle) else {
                // Abgebrochen: zurück auf den Tab, auf dem die Seiten stehen geblieben sind.
                let bleibt = CGFloat(tab.wrappedValue.rawValue)
                MainActor.assumeIsolated { stand.stelle = bleibt }
                return
            }
            tab.wrappedValue = neu
            // Die Markierung steht hier schon fast genau; ohne eigene Animation, damit nichts nachfedert.
            MainActor.assumeIsolated { stand.stelle = CGFloat(stelle) }
        }
    }
}
