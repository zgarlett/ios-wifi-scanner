import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()
    @State private var searchText = ""
    @State private var sortOrder = SortOrder.ip
    @State private var filterType: DeviceType? = nil

    enum SortOrder: String, CaseIterable {
        case ip       = "IP"
        case hostname = "Name"
        case type     = "Type"
        case latency  = "Latency"
    }

    var filteredDevices: [NetworkDevice] {
        var list = scanner.devices
        if let type = filterType {
            list = list.filter { $0.deviceType == type }
        }
        if !searchText.isEmpty {
            list = list.filter {
                $0.ipAddress.localizedCaseInsensitiveContains(searchText) ||
                ($0.hostname?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.macAddress?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.deviceType.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .ip:
            return list
        case .hostname:
            return list.sorted { $0.displayName < $1.displayName }
        case .type:
            return list.sorted { $0.deviceType.rawValue < $1.deviceType.rawValue }
        case .latency:
            return list.sorted { ($0.responseTime ?? .infinity) < ($1.responseTime ?? .infinity) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if scanner.devices.isEmpty && !scanner.isScanning {
                    emptyState
                } else {
                    deviceList
                }
            }
            .navigationTitle("Wi-Fi Scanner")
            .toolbar { toolbar }
            .searchable(text: $searchText, prompt: "Search IP, hostname, MAC…")
        }
        .overlay(alignment: .bottom) {
            if scanner.isScanning { progressBanner }
        }
        .alert("Error", isPresented: .constant(scanner.errorMessage != nil)) {
            Button("OK") { scanner.errorMessage = nil }
        } message: {
            Text(scanner.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No devices found")
                .font(.title2.bold())
            Text("Tap Scan to discover devices on your local network.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Scan Now") { scanner.startScan() }
                .buttonStyle(.borderedProminent)
                .disabled(scanner.isScanning)
        }
    }

    private var deviceList: some View {
        List(filteredDevices) { device in
            NavigationLink(destination: DeviceDetailView(device: device)) {
                DeviceRowView(device: device)
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: filteredDevices.map(\.id))
        .overlay(alignment: .top) {
            if let iface = scanner.currentInterface {
                networkBadge(iface: iface)
            }
        }
    }

    private func networkBadge(iface: NetworkInterface) -> some View {
        Label("\(iface.ipAddress)  ·  \(iface.networkPrefix).0/24", systemImage: "wifi")
            .font(.caption2)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
    }

    private var progressBanner: some View {
        VStack(spacing: 6) {
            ProgressView(value: scanner.scanProgress)
                .progressViewStyle(.linear)
            Text(scanner.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Filter by type
            Menu {
                Button("All Types") { filterType = nil }
                Divider()
                ForEach(DeviceType.allCases, id: \.self) { type in
                    Button {
                        filterType = type
                    } label: {
                        Label(type.rawValue, systemImage: type.systemImageName)
                    }
                }
            } label: {
                Image(systemName: filterType == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }

            // Sort menu
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        if sortOrder == order {
                            Label(order.rawValue, systemImage: "checkmark")
                        } else {
                            Text(order.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            if scanner.isScanning {
                Button("Stop", role: .destructive) { scanner.stopScan() }
            } else {
                Button {
                    scanner.startScan()
                } label: {
                    Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
