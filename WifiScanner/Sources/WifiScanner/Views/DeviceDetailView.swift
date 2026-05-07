import SwiftUI

struct DeviceDetailView: View {
    let device: NetworkDevice

    var body: some View {
        List {
            // Hero
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: device.deviceType.systemImageName)
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text(device.displayName)
                            .font(.title2.bold())
                        Text(device.deviceType.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // Network identity
            Section("Network") {
                InfoRow(label: "IP Address", value: device.ipAddress, copyable: true)
                if let mac = device.macAddress {
                    InfoRow(label: "MAC Address", value: mac, copyable: true)
                    if let vendor = device.macVendor {
                        InfoRow(label: "Vendor", value: vendor)
                    }
                } else {
                    InfoRow(label: "MAC Address", value: "Unavailable (iOS restriction)")
                }
                if let hostname = device.hostname {
                    InfoRow(label: "Hostname", value: hostname, copyable: true)
                }
                if let rt = device.responseTime {
                    InfoRow(label: "Response Time", value: String(format: "%.1f ms", rt))
                }
            }

            // Open ports
            if !device.openPorts.isEmpty {
                Section("Open Ports") {
                    ForEach(device.openPorts, id: \.self) { port in
                        let service = NetworkUtilities.commonPorts.first(where: { $0.0 == port })?.1
                        HStack {
                            Text("\(port)")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            if let service {
                                Text(service)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Bonjour services
            if !device.services.isEmpty {
                Section("Bonjour Services") {
                    ForEach(device.services, id: \.self) { service in
                        Text(service)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Last Seen") {
                InfoRow(label: "Time", value: device.lastSeen.formatted(date: .omitted, time: .standard))
                InfoRow(label: "Date", value: device.lastSeen.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var copyable = false
    @State private var copied = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(copyable ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(copyable ? .primary : .secondary)
                .multilineTextAlignment(.trailing)
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
