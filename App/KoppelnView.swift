import SwiftUI
import VisionKit

/// Koppeln: QR-Code scannen oder Adresse und Code eintippen, dann die Prüfzahl vergleichen.
struct KoppelnView: View {
    @EnvironmentObject private var zustand: AppZustand
    @Environment(\.dismiss) private var schliessen
    @StateObject private var kopplung = Kopplung()
    @State private var einladung: Einladung?
    @State private var adresse = ""
    @State private var code = ""
    @State private var hinweis: String?

    init(einladung: Einladung?) {
        _einladung = State(initialValue: einladung)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let einladung {
                    ablauf(einladung)
                } else {
                    eingabe
                }
            }
            .navigationTitle("Server einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
            }
        }
    }

    // MARK: Eingabe

    private var eingabe: some View {
        Form {
            Section {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner { text in
                        if let gefunden = Einladung(text: text) {
                            einladung = gefunden
                        } else {
                            hinweis = "Das ist kein Kopplungs-Code von Personal API."
                        }
                    }
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
                } else {
                    Text("Die Kamera steht hier nicht zur Verfügung. Scanne den QR-Code mit der Kamera-App des iPhones oder gib den Code unten ein.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("QR-Code scannen")
            } footer: {
                Text(hinweis ?? "Den QR-Code zeigt dein Server im Dashboard unter „Geräte“ → „App koppeln“.")
            }
            Section {
                TextField("Adresse, z. B. 192.168.0.10:8000", text: $adresse)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Code, 6 Ziffern", text: $code)
                    .keyboardType(.numberPad)
                Button("Koppeln") {
                    if let eingegeben = Einladung(adresse: adresse, code: code) {
                        einladung = eingegeben
                    } else {
                        hinweis = "Adresse oder Code fehlt. Die verschlüsselte Adresse (https) geht nur mit dem QR-Code."
                    }
                }
                .disabled(adresse.isEmpty || code.isEmpty)
            } header: {
                Text("Oder von Hand")
            } footer: {
                Text("Von Hand geht nur die unverschlüsselte Adresse. Mit dem QR-Code lernt die App auch den Fingerabdruck deines Servers.")
            }
        }
    }

    // MARK: Ablauf

    private func ablauf(_ einladung: Einladung) -> some View {
        VStack(spacing: 20) {
            Spacer()
            switch kopplung.stand {
            case .verbinden:
                ProgressView()
                Text("Verbinde mit \(einladung.adresse) …")
                    .foregroundStyle(.secondary)
            case .wartet(let pruefzahl):
                Text("Prüfzahl")
                    .font(.headline)
                Text(verbatim: String(pruefzahl.prefix(3)) + " " + String(pruefzahl.suffix(3)))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("Prüfzahl \(pruefzahl.map(String.init).joined(separator: " "))")
                Text("Öffne am Server das Dashboard, Bereich „Geräte“. Steht dort bei der wartenden App dieselbe Zahl, bestätige sie. Sonst lehne ab.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                ProgressView()
            case .fertig:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Gekoppelt")
                    .font(.title2.bold())
            case .fehler(let text):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text(text)
                    .multilineTextAlignment(.center)
                Button("Noch einmal") {
                    self.einladung = nil
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
            Label(einladung.verschluesselt ? "Verschlüsselt, Fingerabdruck aus dem QR-Code" : "Unverschlüsselt (nur im Heimnetz verwenden)",
                  systemImage: einladung.verschluesselt ? "lock.fill" : "lock.open")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .task(id: einladung) {
            await kopplung.ausfuehren(einladung, zustand: zustand)
            if kopplung.stand == .fertig {
                try? await Task.sleep(nanoseconds: 900_000_000)
                schliessen()
            }
        }
    }
}

/// Kamera-Scanner für QR-Codes (VisionKit).
struct QRScanner: UIViewControllerRepresentable {
    let gefunden: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced,
                                                recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(gefunden: gefunden)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let gefunden: (String) -> Void

        init(gefunden: @escaping (String) -> Void) {
            self.gefunden = gefunden
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for eintrag in addedItems {
                if case .barcode(let barcode) = eintrag, let text = barcode.payloadStringValue {
                    gefunden(text)
                }
            }
        }
    }
}
