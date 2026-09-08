import Darwin

enum DeviceDetector {
    /// Returns unique IPv4 addresses on up/running `en*` interfaces, ordered by name.
    static func activeIPv4Addresses() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }
        return activeIPv4Addresses(startingAt: firstAddr)
    }

    /// The linked-list boundary permits synthetic interfaces without querying the host.
    static func activeIPv4Addresses(startingAt firstAddr: UnsafeMutablePointer<ifaddrs>?) -> [String] {
        var results: [(name: String, ip: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let ifa = current {
            let name = String(cString: ifa.pointee.ifa_name)
            let activeFlags = UInt32(IFF_UP | IFF_RUNNING)
            guard name.hasPrefix("en"), ifa.pointee.ifa_flags & activeFlags == activeFlags else {
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
                if !ip.hasPrefix("169.254.") {
                    results.append((name, ip))
                }
            }
            current = ifa.pointee.ifa_next
        }

        return results.sorted { $0.name < $1.name }.reduce(into: []) { addresses, interface in
            if !addresses.contains(interface.ip) { addresses.append(interface.ip) }
        }
    }

}
