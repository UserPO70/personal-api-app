import PhotosUI
import SwiftUI

/// Die Knöpfe zum Erfassen von Essen: der Foto-Knopf für „Heute“, Barcode, Text, Favorit und Mediathek für „Essen“,
/// dazu „Foto ergänzen“ für die eben erfasste Mahlzeit. Bringt Kamera, Eingabeblätter und die Frage nach der
/// Zustimmung selbst mit und lässt sich deshalb auf jedem Bildschirm einsetzen.
struct Erfassen: View {
    private struct Aufnahme {
        let id = UUID()
        let bilder: [UIImage]
        let quelle: FotoBlatt.Quelle
        /// Gesetzt, wenn das Foto zur eben erfassten Mahlzeit dazukommt.
        let ergaenzt: Warteschlange.Letzte?
    }

    private enum Blatt: Identifiable {
        case foto(Aufnahme)
        case barcode, text, favoriten, zustimmung

        var id: String {
            switch self {
            case .foto(let aufnahme): return aufnahme.id.uuidString
            case .barcode: return "barcode"
            case .text: return "text"
            case .favoriten: return "favoriten"
            case .zustimmung: return "zustimmung"
            }
        }
    }

    /// Was dieser Einsatz zeigt. Jeder Knopf steht nur an einer Stelle der App.
    enum Umfang {
        /// Nur der Foto-Knopf, breit: unten auf „Heute“, in Daumenreichweite.
        case foto
        /// Barcode, Text, Favorit und Mediathek: oben im Tab „Essen“.
        case uebrige
        /// „Eben erfasst“ mit dem Knopf „Foto ergänzen“: im Tab „Essen“, solange die Mahlzeit jünger als 30 Minuten ist.
        case ergaenzen
    }

    let umfang: Umfang

    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @State private var blatt: Blatt?
    @State private var kamera = false
    @State private var kameraErgaenzt: Warteschlange.Letzte?
    @State private var aufgenommen: UIImage?
    @State private var auswahl: [PhotosPickerItem] = []
    @State private var auswahlErgaenzen: [PhotosPickerItem] = []
    @State private var hinweis: String?

    var body: some View {
        inhalt
            .disabled(zustand.demo)
            .onChange(of: auswahl) { _, neu in
                guard !neu.isEmpty else { return }
                auswahl = []
                mediathekLaden(neu, ergaenzt: nil)
            }
            .onChange(of: auswahlErgaenzen) { _, neu in
                guard !neu.isEmpty else { return }
                auswahlErgaenzen = []
                mediathekLaden(neu, ergaenzt: schlange.letzte)
            }
            .fullScreenCover(isPresented: $kamera, onDismiss: kameraZu) {
                Kamera { bild in
                    aufgenommen = bild
                    kamera = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $blatt) { blatt in
                switch blatt {
                case .foto(let aufnahme):
                    FotoBlatt(bilder: aufnahme.bilder, quelle: aufnahme.quelle, ergaenzt: aufnahme.ergaenzt)
                case .barcode:
                    BarcodeBlatt()
                case .text:
                    TextBlatt()
                case .favoriten:
                    FavoritenBlatt()
                case .zustimmung:
                    ZustimmungView()
                }
            }
            .alert("Hinweis", isPresented: hinweisZeigen) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(hinweis ?? "")
            }
    }

    @ViewBuilder
    private var inhalt: some View {
        switch umfang {
        case .foto:
            Button {
                if claudeErlaubt() {
                    if Kamera.vorhanden {
                        kameraErgaenzt = nil
                        kamera = true
                    } else {
                        hinweis = "Dieses Gerät hat keine Kamera. Nimm im Tab Essen ein Foto aus der Mediathek."
                    }
                }
            } label: {
                Label("Essen fotografieren", systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(Color.aufAkzent)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .uebrige:
            HStack(spacing: Abstand.eng) {
                knopf("Barcode", "barcode.viewfinder") { blatt = .barcode }
                knopf("Text", "text.cursor") {
                    if claudeErlaubt() { blatt = .text }
                }
                knopf("Favorit", "star") { blatt = .favoriten }

                if zustand.zustimmung == .ja {
                    PhotosPicker(selection: $auswahl, maxSelectionCount: Eintrag.maxFotos,
                                 selectionBehavior: .ordered, matching: .images) {
                        beschriftung("Mediathek", "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Fotos aus der Mediathek, bis zu \(Eintrag.maxFotos)")
                }
            }
        case .ergaenzen:
            if let letzte = schlange.letzte {
                HStack(spacing: Abstand.kachel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Eben erfasst")
                            .font(.footnote)
                            .foregroundStyle(Color.text2)
                        Text("\(letzte.titel ?? "Mahlzeit") · \(letzte.zeit.formatted(date: .omitted, time: .shortened))")
                            .lineLimit(1)
                    }
                    Spacer(minLength: Abstand.eng)
                    if Kamera.vorhanden {
                        Button {
                            if claudeErlaubt() {
                                kameraErgaenzt = letzte
                                kamera = true
                            }
                        } label: {
                            Label("Foto ergänzen", systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                    } else if zustand.zustimmung == .ja {
                        PhotosPicker(selection: $auswahlErgaenzen, maxSelectionCount: Eintrag.maxFotos,
                                     selectionBehavior: .ordered, matching: .images) {
                            Label("Foto ergänzen", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var hinweisZeigen: Binding<Bool> {
        Binding(get: { hinweis != nil }, set: { if !$0 { hinweis = nil } })
    }

    private func knopf(_ name: String, _ symbol: String, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            beschriftung(name, symbol)
        }
        .buttonStyle(.bordered)
    }

    private func beschriftung(_ name: String, _ symbol: String) -> some View {
        VStack(spacing: Abstand.winzig) {
            Image(systemName: symbol)
                .font(.title3)
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    /// Foto und Text gehen über den Server an Claude: nur mit Zustimmung.
    private func claudeErlaubt() -> Bool {
        switch zustand.zustimmung {
        case .ja:
            return true
        case .offen:
            blatt = .zustimmung
            return false
        case .nein:
            hinweis = "Die Fotoanalyse ist ausgeschaltet. Du kannst sie in den Einstellungen einschalten. Barcode und Favoriten gehen auch so."
            return false
        }
    }

    private func mediathekLaden(_ auswahl: [PhotosPickerItem], ergaenzt: Warteschlange.Letzte?) {
        Task {
            let bilder = await FotoBlatt.laden(auswahl)
            if bilder.isEmpty {
                hinweis = "Die Bilder lassen sich nicht lesen."
            } else {
                blatt = .foto(Aufnahme(bilder: bilder, quelle: .mediathek, ergaenzt: ergaenzt))
            }
        }
    }

    private func kameraZu() {
        let ergaenzt = kameraErgaenzt
        kameraErgaenzt = nil
        guard let bild = aufgenommen else { return }
        aufgenommen = nil
        blatt = .foto(Aufnahme(bilder: [bild], quelle: .kamera, ergaenzt: ergaenzt))
    }
}
