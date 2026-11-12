import SwiftUI
import UIKit

@main
struct PersonalAPIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ProbeView() }
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
