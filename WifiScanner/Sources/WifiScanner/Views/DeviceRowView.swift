import SwiftUI

struct DeviceRowView: View {
    let device: NetworkDevice

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.deviceType.systemImageName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(device.ipAddress, systemImage: "network")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let mac = device.macAddress {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Label(mac, systemImage: "personalhotspot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !device.services.isEmpty {
                    Text(device.services.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let rt = device.responseTime {
                Text("\(Int(rt)) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
