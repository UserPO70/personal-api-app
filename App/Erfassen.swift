import PhotosUI
import SwiftUI

/// Die Knöpfe zum Erfassen von Essen: der Foto-Knopf für „Heute“, Barcode, Text, Favorit und Mediathek für „Essen“.
/// Bringt Kamera, Eingabeblätter und die Frage nach der Zustimmung selbst mit und lässt sich deshalb
/// auf jedem Bildschirm einsetzen.
struct Erfassen: View {
    private struct Aufnahme {
        let id = UUID()
        let bild: UIImage
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
    }

    let umfang: Umfang

    @EnvironmentObject private var zustand: AppZustand
    @State private var blatt: Blatt?
    @State private var kamera = false
    @State private var aufgenommen: UIImage?
    @State private var auswahl: PhotosPickerItem?
    @State private var hinweis: String?

    var body: some View {
        HStack(spacing: 8) {
            if umfang == .foto {
                Button {
                    if claudeErlaubt() {
                        if Kamera.vorhanden {
                            kamera = true
                        } else {
                            hinweis = "Dieses Gerät hat keine Kamera. Nimm im Tab Essen ein Foto aus der Mediathek."
                        }
                    }
                } label: {
                    Label("Essen fotografieren", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                knopf("Barcode", "barcode.viewfinder") { blatt = .barcode }
                knopf("Text", "text.cursor") {
                    if claudeErlaubt() { blatt = .text }
                }
                knopf("Favorit", "star") { blatt = .favoriten }

                if zustand.zustimmung == .ja {
                    PhotosPicker(selection: $auswahl, matching: .images) {
                        beschriftung("Mediathek", "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Foto aus der Mediathek")
                }
            }
        }
        .disabled(zustand.demo)
        .onChange(of: auswahl) { _, neu in
            guard let neu else { return }
            auswahl = nil
            Task {
                if let daten = try? await neu.loadTransferable(type: Data.self), let bild = UIImage(data: daten) {
                    blatt = .foto(Aufnahme(bild: bild))
                } else {
                    hinweis = "Das Bild lässt sich nicht lesen."
                }
            }
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
                FotoBlatt(bild: aufnahme.bild)
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
        VStack(spacing: 4) {
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

    private func kameraZu() {
        guard let bild = aufgenommen else { return }
        aufgenommen = nil
        blatt = .foto(Aufnahme(bild: bild))
    }
}
