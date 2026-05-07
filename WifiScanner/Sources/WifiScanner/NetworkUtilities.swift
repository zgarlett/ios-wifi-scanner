import Foundation
import Network
import Darwin

struct NetworkInterface {
    let name: String
    let ipAddress: String
    let subnetMask: String
    let broadcastAddress: String

    var networkPrefix: String {
        let parts = ipAddress.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return ipAddress }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    var hostRange: ClosedRange<Int> { 1...254 }
}

enum NetworkUtilities {

    // MARK: - Interface detection

    static func wifiInterface() -> NetworkInterface? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp       = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let family     = current.pointee.ifa_addr.pointee.sa_family

            if isUp && !isLoopback && family == UInt8(AF_INET) {
                let name = String(cString: current.pointee.ifa_name)
                guard name == "en0" else { ptr = current.pointee.ifa_next; continue }

                var ip = ""
                var mask = ""
                var broadcast = ""

                var addr = current.pointee.ifa_addr.pointee
                ip = sockaddrToIP(&addr)

                if let netmask = current.pointee.ifa_netmask {
                    var nm = netmask.pointee
                    mask = sockaddrToIP(&nm)
                }
                if let dstaddr = current.pointee.ifa_dstaddr {
                    var bc = dstaddr.pointee
                    broadcast = sockaddrToIP(&bc)
                }

                return NetworkInterface(name: name, ipAddress: ip, subnetMask: mask, broadcastAddress: broadcast)
            }
            ptr = current.pointee.ifa_next
        }
        return nil
    }

    private static func sockaddrToIP(_ addr: inout sockaddr) -> String {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
        return String(cString: hostname)
    }

    // MARK: - ARP cache (via sysctl — no Process needed on iOS)

    static func readARPCache() async -> [String: String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: fetchARPTable())
            }
        }
    }

    private static func fetchARPTable() -> [String: String] {
        // net.route.0.inet.flags.llinfo  →  all ARP entries
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var needed = 0
        guard sysctl(&mib, u_int(mib.count), nil, &needed, nil, 0) == 0, needed > 0 else { return [:] }

        var buf = [UInt8](repeating: 0, count: needed)
        guard sysctl(&mib, u_int(mib.count), &buf, &needed, nil, 0) == 0 else { return [:] }

        var result: [String: String] = [:]
        var offset = 0

        while offset + MemoryLayout<rt_msghdr_ws>.size <= needed {
            let msgLen: Int = buf.withUnsafeBytes {
                Int($0.load(fromByteOffset: offset, as: rt_msghdr_ws.self).rtm_msglen)
            }
            guard msgLen > 0, offset + msgLen <= needed else { break }
            if let (ip, mac) = parseARPEntry(buf: buf, baseOffset: offset) {
                result[ip] = mac
            }
            offset += msgLen
        }
        return result
    }

    private static func parseARPEntry(buf: [UInt8], baseOffset: Int) -> (String, String)? {
        buf.withUnsafeBytes { raw -> (String, String)? in
            let hdr = raw.load(fromByteOffset: baseOffset, as: rt_msghdr_ws.self)
            var addrOff = baseOffset + MemoryLayout<rt_msghdr_ws>.size

            var ip: String?
            var mac: String?

            for bit in 0..<Int(RTAX_MAX) {
                guard (Int32(hdr.rtm_addrs) & (1 << bit)) != 0 else { continue }
                guard addrOff + MemoryLayout<sockaddr>.size <= buf.count else { break }

                let sa = raw.load(fromByteOffset: addrOff, as: sockaddr.self)

                if bit == Int(RTAX_DST) && Int32(sa.sa_family) == AF_INET {
                    guard addrOff + MemoryLayout<sockaddr_in>.size <= buf.count else { break }
                    var sin = raw.load(fromByteOffset: addrOff, as: sockaddr_in.self)
                    var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &sin.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                    ip = String(cString: ipBuf)
                }

                if bit == Int(RTAX_GATEWAY) && Int32(sa.sa_family) == AF_LINK {
                    guard addrOff + MemoryLayout<sockaddr_dl>.size <= buf.count else { break }
                    let sdl = raw.load(fromByteOffset: addrOff, as: sockaddr_dl.self)
                    let nlen = Int(sdl.sdl_nlen)
                    let alen = Int(sdl.sdl_alen)
                    if alen == 6 {
                        // sdl_data is at byte offset 8 within sockaddr_dl
                        let dataStart = addrOff + 8 + nlen
                        if dataStart + 6 <= buf.count {
                            let bytes = (0..<6).map { buf[dataStart + $0] }
                            let candidate = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                            if candidate != "00:00:00:00:00:00" {
                                mac = candidate
                            }
                        }
                    }
                }

                let saLen = max(Int(sa.sa_len), 4)
                addrOff += (saLen + 3) & ~3
            }

            guard let i = ip, let m = mac else { return nil }
            return (i, m)
        }
    }

    // MARK: - Reverse DNS

    static func reverseDNS(for ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_STREAM
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(ip, nil, &hints, &res) == 0, let first = res else {
                    freeaddrinfo(res)
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(res) }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let code = getnameinfo(
                    first.pointee.ai_addr,
                    first.pointee.ai_addrlen,
                    &hostname,
                    socklen_t(hostname.count),
                    nil, 0,
                    NI_NAMEREQD
                )
                let name = code == 0 ? String(cString: hostname) : nil
                continuation.resume(returning: name == ip ? nil : name)
            }
        }
    }

    // MARK: - Port probing

    static let commonPorts: [(Int, String)] = [
        (22,   "SSH"),
        (23,   "Telnet"),
        (80,   "HTTP"),
        (443,  "HTTPS"),
        (445,  "SMB"),
        (548,  "AFP"),
        (554,  "RTSP"),
        (631,  "IPP/Printer"),
        (3389, "RDP"),
        (5000, "UPnP"),
        (5900, "VNC"),
        (8080, "HTTP-Alt"),
        (8443, "HTTPS-Alt"),
        (9100, "RAW Print"),
    ]

    static func probePorts(ip: String, timeout: TimeInterval = 0.5) async -> (openPorts: [Int], services: [String]) {
        await withTaskGroup(of: (Int, String, Bool).self) { group in
            for (port, service) in commonPorts {
                group.addTask {
                    let open = await isPortOpen(host: ip, port: port, timeout: timeout)
                    return (port, service, open)
                }
            }
            var openPorts: [Int] = []
            var services: [String] = []
            for await (port, service, isOpen) in group {
                if isOpen {
                    openPorts.append(port)
                    services.append(service)
                }
            }
            return (openPorts.sorted(), services)
        }
    }

    private static func isPortOpen(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )
            let lock = NSLock()
            var done = false
            let finish: (Bool) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !done else { return }
                done = true
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:     finish(true)
                case .failed(_): finish(false)
                case .cancelled: finish(false)
                default:         break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }

    // MARK: - Device type inference

    static func inferDeviceType(ports: [Int], services: [String], hostname: String?) -> DeviceType {
        let portSet = Set(ports)
        let hn = hostname?.lowercased() ?? ""

        if portSet.contains(631) || portSet.contains(9100)                    { return .printer }
        if portSet.contains(554)                                               { return .tv }
        if portSet.contains(3389) || portSet.contains(445) || portSet.contains(548) || portSet.contains(5900) || portSet.contains(22) { return .computer }

        if hn.contains("iphone") || hn.contains("android")                    { return .phone }
        if hn.contains("ipad")                                                 { return .tablet }
        if hn.contains("macbook") || hn.contains("imac") || hn.contains("mac-") { return .computer }
        if hn.contains("appletv") || hn.contains("apple-tv") || hn.contains("roku") || hn.contains("firetv") { return .tv }
        if hn.contains("router") || hn.contains("gateway") || hn.contains("airport") { return .router }
        if hn.contains("printer") || hn.contains("print")                     { return .printer }

        if portSet.contains(80) || portSet.contains(443)                       { return .router }
        if !portSet.isEmpty                                                     { return .iot }
        return .unknown
    }
}
