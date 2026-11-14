import SwiftUI

/// Die Tabs der App. Zwischen ihnen wird gewischt: Der Nachbar gleitet mit dem Finger herein.
enum Reiter: Int, CaseIterable, Identifiable {
    case heute, essen, einstellungen

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .heute: return "Heute"
        case .essen: return "Essen"
        case .einstellungen: return "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .heute: return "sun.max"
        case .essen: return "fork.knife"
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
    @Binding var tab: Reiter

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Reiter.allCases) { eintrag in
                Button {
                    withAnimation(.snappy) { tab = eintrag }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: eintrag.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .symbolVariant(tab == eintrag ? .fill : .none)
                        Text(eintrag.name)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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
        .padding(.horizontal, 28)
        .padding(.bottom, 2)
    }
}
