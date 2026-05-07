import Foundation
import Network
import Combine

@MainActor
final class NetworkScanner: ObservableObject {
    @Published var devices: [NetworkDevice] = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var statusMessage = "Ready"
    @Published var currentInterface: NetworkInterface?
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?
    private var bonjourBrowser: BonjourBrowser?

    // MARK: - Public API

    func startScan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        scanTask = Task { await performScan() }
    }

    func stopScan() {
        scanTask?.cancel()
        bonjourBrowser?.stop()
        isScanning = false
        statusMessage = "Stopped"
    }

    // MARK: - Scan orchestration

    private func performScan() async {
        isScanning = true
        devices = []
        scanProgress = 0
        errorMessage = nil

        guard let iface = NetworkUtilities.wifiInterface() else {
            errorMessage = "No Wi-Fi interface found. Make sure you are connected to a network."
            isScanning = false
            statusMessage = "No Wi-Fi"
            return
        }
        currentInterface = iface
        statusMessage = "Scanning \(iface.networkPrefix).0/24..."

        // Phase 1: Start Bonjour discovery in parallel
        let browser = BonjourBrowser()
        bonjourBrowser = browser
        browser.start()

        // Phase 2: TCP/ICMP sweep of the /24
        let prefix = iface.networkPrefix
        let range = iface.hostRange
        let total = Double(range.upperBound - range.lowerBound + 1)
        var completed = 0.0

        await withTaskGroup(of: NetworkDevice?.self) { group in
            for host in range {
                let ip = "\(prefix).\(host)"
                group.addTask { [weak self] in
                    await self?.probeHost(ip: ip)
                }
            }

            for await result in group {
                completed += 1
                scanProgress = completed / total
                if let device = result {
                    upsertDevice(device)
                }
            }
        }

        // Phase 3: Read ARP cache to fill in MACs
        statusMessage = "Reading ARP cache..."
        let arp = await NetworkUtilities.readARPCache()
        for (ip, mac) in arp {
            if let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
                devices[idx].macAddress = mac
            } else {
                // Device replied to ARP but missed our TCP probe — add it
                var device = NetworkDevice(ipAddress: ip, macAddress: mac)
                device.deviceType = .unknown
                upsertDevice(device)
            }
        }

        // Phase 4: Merge Bonjour results
        statusMessage = "Merging Bonjour services..."
        let bonjourResults = browser.results
        browser.stop()
        for (ip, services) in bonjourResults {
            if let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
                let merged = Array(Set(devices[idx].services + services))
                devices[idx].services = merged
            }
        }

        // Re-infer device types with enriched data
        for i in devices.indices {
            devices[i].deviceType = NetworkUtilities.inferDeviceType(
                ports: devices[i].openPorts,
                services: devices[i].services,
                hostname: devices[i].hostname
            )
        }

        devices.sort { $0.ipAddress.ipSortKey < $1.ipAddress.ipSortKey }

        isScanning = false
        scanProgress = 1
        statusMessage = "Found \(devices.count) device\(devices.count == 1 ? "" : "s")"
    }

    // MARK: - Single host probe

    private func probeHost(ip: String) async -> NetworkDevice? {
        let start = Date()

        // Try TCP connect to port 80 first as a fast reachability check
        let (openPorts, services) = await NetworkUtilities.probePorts(ip: ip, timeout: 0.4)

        // If no ports are open, try a second round with a short ICMP-like trick
        // (actual ICMP requires entitlements; we use the ARP phase instead)
        guard !openPorts.isEmpty else { return nil }

        let elapsed = Date().timeIntervalSince(start) * 1000

        // Reverse DNS
        let hostname = await NetworkUtilities.reverseDNS(for: ip)

        let deviceType = NetworkUtilities.inferDeviceType(
            ports: openPorts,
            services: services,
            hostname: hostname
        )

        return NetworkDevice(
            ipAddress: ip,
            macAddress: nil,
            hostname: hostname,
            openPorts: openPorts,
            services: services,
            deviceType: deviceType,
            responseTime: elapsed
        )
    }

    // MARK: - Helpers

    private func upsertDevice(_ device: NetworkDevice) {
        if let idx = devices.firstIndex(where: { $0.ipAddress == device.ipAddress }) {
            // Merge: prefer non-nil values from the new entry
            var existing = devices[idx]
            if let mac = device.macAddress { existing.macAddress = mac }
            if let hn = device.hostname    { existing.hostname = hn }
            if !device.openPorts.isEmpty   { existing.openPorts = Array(Set(existing.openPorts + device.openPorts)).sorted() }
            if !device.services.isEmpty    { existing.services = Array(Set(existing.services + device.services)) }
            if let rt = device.responseTime { existing.responseTime = rt }
            devices[idx] = existing
        } else {
            devices.append(device)
        }
    }
}

// MARK: - Bonjour browser

private final class BonjourBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private(set) var results: [String: [String]] = [:]  // ip -> [service names]
    private var resolving: [NetService] = []

    private let serviceTypes = [
        "_http._tcp.",
        "_https._tcp.",
        "_ssh._tcp.",
        "_smb._tcp.",
        "_afpovertcp._tcp.",
        "_rfb._tcp.",         // VNC
        "_ipp._tcp.",         // Printer
        "_airplay._tcp.",
        "_raop._tcp.",
        "_homekit._tcp.",
        "_googlecast._tcp.",
        "_spotify-connect._tcp.",
        "_daap._tcp.",
    ]

    func start() {
        browser.delegate = self
        for type in serviceTypes {
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    func stop() {
        browser.stop()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 3)
        resolving.append(service)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            if let ip = extractIPv4(from: data) {
                results[ip, default: []].append(sender.type)
            }
        }
    }

    private func extractIPv4(from data: Data) -> String? {
        data.withUnsafeBytes { ptr -> String? in
            guard let base = ptr.baseAddress else { return nil }
            let sa = base.assumingMemoryBound(to: sockaddr.self).pointee
            guard sa.sa_family == AF_INET else { return nil }
            let sin = base.assumingMemoryBound(to: sockaddr_in.self).pointee
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addr = sin.sin_addr
            inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buf)
        }
    }
}

// MARK: - IP sort helper

private extension String {
    var ipSortKey: Int {
        let parts = split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }
}
