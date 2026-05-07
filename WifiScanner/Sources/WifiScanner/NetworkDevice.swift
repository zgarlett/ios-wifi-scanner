import Foundation

enum DeviceType: String, CaseIterable {
    case router = "Router"
    case phone = "Phone"
    case computer = "Computer"
    case tablet = "Tablet"
    case tv = "Smart TV"
    case printer = "Printer"
    case iot = "IoT Device"
    case unknown = "Unknown"

    var systemImageName: String {
        switch self {
        case .router:   return "wifi.router"
        case .phone:    return "iphone"
        case .computer: return "desktopcomputer"
        case .tablet:   return "ipad"
        case .tv:       return "tv"
        case .printer:  return "printer"
        case .iot:      return "homekit"
        case .unknown:  return "questionmark.circle"
        }
    }
}

struct NetworkDevice: Identifiable, Equatable {
    let id = UUID()
    var ipAddress: String
    var macAddress: String?
    var hostname: String?
    var openPorts: [Int] = []
    var services: [String] = []
    var deviceType: DeviceType = .unknown
    var responseTime: Double?
    var lastSeen: Date = Date()

    var displayName: String {
        hostname ?? ipAddress
    }

    var macVendor: String? {
        guard let mac = macAddress else { return nil }
        return MacVendorLookup.vendor(for: mac)
    }

    static func == (lhs: NetworkDevice, rhs: NetworkDevice) -> Bool {
        lhs.ipAddress == rhs.ipAddress
    }
}

enum MacVendorLookup {
    // Partial OUI prefix lookup — covers the most common vendors seen on home networks.
    private static let oui: [String: String] = [
        "00:50:56": "VMware",
        "00:0C:29": "VMware",
        "00:1A:11": "Google",
        "F4:F5:DB": "Google",
        "B8:27:EB": "Raspberry Pi",
        "DC:A6:32": "Raspberry Pi",
        "E4:5F:01": "Raspberry Pi",
        "00:17:88": "Philips Hue",
        "EC:B5:FA": "Apple",
        "A4:C3:F0": "Apple",
        "00:03:93": "Apple",
        "00:0A:95": "Apple",
        "3C:D9:2B": "Hewlett-Packard",
        "00:21:5A": "Hewlett-Packard",
        "00:26:B9": "Dell",
        "F8:DB:88": "Dell",
        "00:50:BA": "D-Link",
        "1C:7E:E5": "D-Link",
        "CC:40:D0": "Cisco",
        "00:1B:54": "Cisco",
        "04:18:D6": "Cisco",
        "00:18:E7": "Netgear",
        "20:E5:2A": "Netgear",
        "00:26:F2": "Netgear",
        "18:35:D1": "ASUS",
        "00:23:54": "ASUS",
        "AC:84:C6": "ASUS",
        "00:1D:7E": "Linksys",
        "C0:56:27": "Samsung",
        "84:25:19": "Samsung",
        "00:1C:62": "Samsung",
        "00:AA:BB": "Intel",
        "8C:EC:4B": "Intel",
        "00:23:14": "Intel",
        "00:E0:4C": "Realtek",
    ]

    static func vendor(for mac: String) -> String? {
        let prefix = mac.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: ":-"))
            .prefix(3)
            .joined(separator: ":")
        return oui[prefix]
    }
}
