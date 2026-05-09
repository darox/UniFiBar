import Darwin

enum DeviceDetector {
    /// Returns all active IPv4 addresses on `en*` interfaces, ordered by interface name.
    /// WiFi interfaces (en0) typically come first, followed by Thunderbolt/Ethernet (en1+).
    static func activeIPv4Addresses() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var results: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let ifa = current {
            let name = String(cString: ifa.pointee.ifa_name)
            guard name.hasPrefix("en") else {
                current = ifa.pointee.ifa_next
                continue
            }

            guard let addr = ifa.pointee.ifa_addr else {
                current = ifa.pointee.ifa_next
                continue
            }

            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) else {
                current = ifa.pointee.ifa_next
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let length = hostname.firstIndex(of: 0).map { Int($0) } ?? hostname.count
                let ip = String(decoding: hostname.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if !ip.hasPrefix("169.254") && !results.contains(ip) {
                    results.append(ip)
                }
            }
            current = ifa.pointee.ifa_next
        }

        return results
    }

    /// Returns the IPv4 address of the first active `en*` interface (WiFi or Ethernet).
    static func activeIPv4Address() -> String? {
        activeIPv4Addresses().first
    }
}