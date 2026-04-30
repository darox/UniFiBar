import SwiftUI

struct VPNSection: View {
    let tunnels: [VPNTunnelDTO]

    var body: some View {
        SectionHeader(title: "VPN")

        ForEach(tunnels) { tunnel in
            let connected = tunnel.isConnected
            HStack(spacing: 6) {
                Image(systemName: connected ? "lock.shield" : "lock.slash")
                    .foregroundStyle(connected ? .green : .red)
                    .frame(width: 20, alignment: .center)
                Text(String(((tunnel.name?.isEmpty == true ? nil : tunnel.name) ?? tunnel.id).prefix(128)))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(connected ? "Connected" : "Down")
                    .foregroundStyle(connected ? Color.secondary : Color.red)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
    }
}
