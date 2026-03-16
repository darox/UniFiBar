import Darwin

enum DeviceDetector {
    /// Returns the IPv4 address of the first active `en*` interface (WiFi or Ethernet).
    static func activeIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let ifa = current {
            let name = String(cString: ifa.pointee.ifa_name)
            let family = ifa.pointee.ifa_addr.pointee.sa_family

            // Match any en* interface (en0 = WiFi, en1+ = Ethernet/Thunderbolt)
            if name.hasPrefix("en") && family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    ifa.pointee.ifa_addr,
                    socklen_t(ifa.pointee.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil, 0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let length = hostname.firstIndex(of: 0).map { Int($0) } ?? hostname.count
                    let ip = String(decoding: hostname.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    // Skip link-local addresses (169.254.x.x)
                    if !ip.hasPrefix("169.254") {
                        return ip
                    }
                }
            }
            current = ifa.pointee.ifa_next
        }

        return nil
    }
}
