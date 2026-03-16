import SwiftUI

@main
struct UniFiBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var controller: StatusBarController {
        appDelegate.controller
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller)
                .frame(width: 320)
        } label: {
            StatusBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Window("UniFiBar Setup", id: "setup") {
            SetupView(controller: controller)
        }
        .windowResizability(.contentSize)

        Window("Preferences", id: "preferences") {
            PreferencesView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}
