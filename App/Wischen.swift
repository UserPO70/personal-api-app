import SwiftUI

/// Die Tabs der App. Zwischen ihnen wird gewischt: Der Nachbar gleitet mit dem Finger herein.
enum Reiter: Int, CaseIterable, Identifiable {
    case heute, essen, auswertungen, einstellungen

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .heute: return "Heute"
        case .essen: return "Essen"
        case .auswertungen: return "Auswertungen"
        case .einstellungen: return "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .heute: return "sun.max"
        case .essen: return "fork.knife"
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

/// Die Leiste unten. Eine eigene statt der von iOS, weil nur so die Tabs mit dem Finger mitgleiten können.
struct Tableiste: View {
    /// So viel Platz hält jede Seite unten für die Leiste frei.
    static let hoehe: CGFloat = 64

    @Binding var tab: Reiter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Reiter.allCases) { eintrag in
                Button {
                    withAnimation(.snappy) { tab = eintrag }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: eintrag.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .symbolVariant(tab == eintrag ? .fill : .none)
                            .frame(height: 24)
                        Text(eintrag.name)
                            // Feste Größe wie in der Tab-Leiste von iOS, damit alle vier Namen gleich groß bleiben.
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(tab == eintrag ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        if tab == eintrag {
                            Capsule().fill(Color.primary.opacity(0.08))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(eintrag.name)
                .accessibilityAddTraits(tab == eintrag ? .isSelected : [])
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

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: $tab, bildschirme: seiten.map { UIHostingController(rootView: $0) })
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
        blaetterer.setViewControllers([koordinator.bildschirme[tab.rawValue]],
                                      direction: tab.rawValue > stelle ? .forward : .reverse, animated: true)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var tab: Binding<Reiter>
        let bildschirme: [UIViewController]

        init(tab: Binding<Reiter>, bildschirme: [UIViewController]) {
            self.tab = tab
            self.bildschirme = bildschirme
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
                  let stelle = bildschirme.firstIndex(of: sichtbar), let neu = Reiter(rawValue: stelle) else { return }
            tab.wrappedValue = neu
        }
    }
}
