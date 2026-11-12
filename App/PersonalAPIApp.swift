import SwiftUI
import UIKit

@main
struct PersonalAPIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var zustand = AppZustand()

    var body: some Scene {
        WindowGroup {
            Group {
                if zustand.verbindung != nil || zustand.demo {
                    HauptView()
                } else {
                    WillkommenView()
                }
            }
            .environmentObject(zustand)
            // QR-Code mit der Kamera-App gescannt: personal-api://koppeln?...
            .onOpenURL { url in
                zustand.einladung = Einladung(text: url.absoluteString)
            }
            .sheet(item: $zustand.einladung) { einladung in
                KoppelnView(einladung: einladung)
                    .environmentObject(zustand)
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// iOS weckt die App, wenn ein Hintergrund-Upload fertig ist.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Hintergrund.shared.abschluss = completionHandler
        _ = Hintergrund.shared.session
    }
}
