import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Startup handled by StatusBarLabel .task modifier
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
