import SwiftUI

struct StatusBarLabel: View {
    let controller: StatusBarController

    var body: some View {
        HStack(spacing: 4) {
            if let nsImage = Self.statusBarIcon {
                Image(nsImage: nsImage)
                    .foregroundStyle(controller.wifiStatus.statusBarColor)
            } else {
                Image(systemName: controller.wifiStatus.statusBarSymbol)
                    .foregroundStyle(controller.wifiStatus.statusBarColor)
            }
            if let satisfaction = controller.wifiStatus.satisfaction, controller.wifiStatus.isConnected {
                Text("\(satisfaction)%")
                    .monospacedDigit()
            }
            if controller.wifiStatus.activeAlarmCount > 0 {
                Image(systemName: "bell.badge.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .task {
            await controller.start()
        }
    }

    private static let statusBarIcon: NSImage? = {
        // Load from app bundle Resources
        guard let url = Bundle.main.url(forResource: "icon@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}
