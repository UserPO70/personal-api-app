import SwiftUI
import UIKit

enum Bild {
    /// Der Server nimmt höchstens 3,75 MB und kein HEIC.
    static let hoechstens = 3_500_000

    /// Verkleinert auf höchstens `kante` Pixel an der langen Seite und wandelt in JPEG um.
    static func jpeg(_ bild: UIImage, kante: CGFloat = 1600) -> Data? {
        let lang = max(bild.size.width, bild.size.height)
        guard lang > 0 else { return nil }
        let faktor = min(1, kante / lang)
        let ziel = CGSize(width: (bild.size.width * faktor).rounded(), height: (bild.size.height * faktor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let klein = UIGraphicsImageRenderer(size: ziel, format: format).image { _ in
            bild.draw(in: CGRect(origin: .zero, size: ziel))
        }
        for guete in [0.8, 0.6, 0.4] {
            if let daten = klein.jpegData(compressionQuality: guete), daten.count <= hoechstens {
                return daten
            }
        }
        return nil
    }
}

/// Kamera von iOS für ein einzelnes Foto, mit eigenem Auslöser: Nach dem Auslösen geht es sofort weiter,
/// ohne die Frage „Foto benutzen?“ von iOS. Prüfen und Entfernen geht danach in der Übersicht.
struct Kamera: UIViewControllerRepresentable {
    let fertig: (UIImage?) -> Void

    static var vorhanden: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let kamera = UIImagePickerController()
        kamera.sourceType = .camera
        kamera.cameraCaptureMode = .photo
        kamera.delegate = context.coordinator
        // Ohne die Knöpfe von iOS gibt es auch die Rückfrage nach dem Auslösen nicht.
        kamera.showsCameraControls = false
        context.coordinator.kamera = kamera
        let flaeche = Kameraflaeche(frame: UIScreen.main.bounds)
        flaeche.ausloesen = { [weak kamera] in kamera?.takePicture() }
        flaeche.abbrechen = { fertig(nil) }
        kamera.cameraOverlayView = flaeche
        // Das Vorschaubild (4:3) steht sonst oben am Rand: in die Mitte zwischen die schwarzen Ränder schieben.
        let bildschirm = UIScreen.main.bounds.size
        let vorschau = bildschirm.width * 4 / 3
        kamera.cameraViewTransform = CGAffineTransform(translationX: 0, y: max((bildschirm.height - vorschau) / 2, 0))
        return kamera
    }

    func updateUIViewController(_ kamera: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(fertig: fertig)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let fertig: (UIImage?) -> Void
        weak var kamera: UIImagePickerController?

        init(fertig: @escaping (UIImage?) -> Void) {
            self.fertig = fertig
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            fertig(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            fertig(nil)
        }
    }
}

/// Die Bedienung über dem Kamerabild: „Abbrechen“ links, der runde Auslöser in der Mitte.
final class Kameraflaeche: UIView {
    var ausloesen: (() -> Void)?
    var abbrechen: (() -> Void)?

    private let ausloeser = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear

        // Weißer Ring mit weißem Kreis, wie der Auslöser der Kamera-App.
        ausloeser.translatesAutoresizingMaskIntoConstraints = false
        ausloeser.layer.cornerRadius = 38
        ausloeser.layer.borderWidth = 4
        ausloeser.layer.borderColor = UIColor.white.cgColor
        let kreis = UIView()
        kreis.translatesAutoresizingMaskIntoConstraints = false
        kreis.backgroundColor = .white
        kreis.layer.cornerRadius = 30
        kreis.isUserInteractionEnabled = false
        ausloeser.addSubview(kreis)
        ausloeser.accessibilityLabel = "Foto aufnehmen"
        ausloeser.addAction(UIAction { [weak self] _ in
            guard let self, self.ausloeser.isEnabled else { return }
            // Nur einmal auslösen, auch bei schnellem Doppeltippen.
            self.ausloeser.isEnabled = false
            kreis.alpha = 0.5
            self.ausloesen?()
        }, for: .touchUpInside)

        var stil = UIButton.Configuration.plain()
        stil.title = "Abbrechen"
        stil.baseForegroundColor = .white
        let zurueck = UIButton(configuration: stil)
        zurueck.translatesAutoresizingMaskIntoConstraints = false
        zurueck.addAction(UIAction { [weak self] _ in self?.abbrechen?() }, for: .touchUpInside)

        addSubview(ausloeser)
        addSubview(zurueck)
        NSLayoutConstraint.activate([
            ausloeser.widthAnchor.constraint(equalToConstant: 76),
            ausloeser.heightAnchor.constraint(equalToConstant: 76),
            ausloeser.centerXAnchor.constraint(equalTo: centerXAnchor),
            ausloeser.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            kreis.widthAnchor.constraint(equalToConstant: 60),
            kreis.heightAnchor.constraint(equalToConstant: 60),
            kreis.centerXAnchor.constraint(equalTo: ausloeser.centerXAnchor),
            kreis.centerYAnchor.constraint(equalTo: ausloeser.centerYAnchor),
            zurueck.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            zurueck.centerYAnchor.constraint(equalTo: ausloeser.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("nicht aus einem Storyboard")
    }
}
