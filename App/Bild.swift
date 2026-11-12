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

/// Kamera von iOS für ein einzelnes Foto.
struct Kamera: UIViewControllerRepresentable {
    let fertig: (UIImage?) -> Void

    static var vorhanden: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let kamera = UIImagePickerController()
        kamera.sourceType = .camera
        kamera.delegate = context.coordinator
        return kamera
    }

    func updateUIViewController(_ kamera: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(fertig: fertig)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let fertig: (UIImage?) -> Void

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
