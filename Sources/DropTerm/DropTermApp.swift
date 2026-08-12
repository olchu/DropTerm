import SwiftUI

@main
struct DropTermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: .shared)
        }
    }
}
