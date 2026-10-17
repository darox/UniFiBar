import SwiftUI

struct VPNSection: View {
    let tunnels: [VPNTunnelDTO]

    var body: some View {
        SectionHeader(title: "VPN")

        ForEach(tunnels.prefix(DisplayLimits.rows)) { tunnel in
            let connected = tunnel.isConnected
            HStack(spacing: 6) {
                Image(systemName: connected == nil ? "questionmark.circle" : connected == true ? "lock.shield" : "lock.slash")
                    .foregroundStyle(connected == nil ? Color.secondary : connected == true ? Color.green : Color.red)
                    .frame(width: 20, alignment: .center)
                Text(String(((tunnel.name?.isEmpty == true ? nil : tunnel.name) ?? tunnel.id).prefix(128)))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(connected == nil ? "Status unknown" : connected == true ? "Connected" : "Disconnected")
                    .foregroundStyle(connected == false ? Color.red : Color.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
        if tunnels.count > DisplayLimits.rows {
            TruncationNote(hiddenCount: tunnels.count - DisplayLimits.rows, noun: "tunnels")
        }
        Text("Configured tunnels; live status may not be supplied by the controller.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }
}
