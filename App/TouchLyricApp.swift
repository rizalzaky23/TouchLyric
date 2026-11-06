import SwiftUI

@main
struct TouchLyricApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            if let svc = appDelegate.spotifyService {
                SettingsView()
                    .environmentObject(svc)
            }
        }
    }
}
