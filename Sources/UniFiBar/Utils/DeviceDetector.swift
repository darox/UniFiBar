import Darwin

enum DeviceDetector {
    static func en0IPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var address: String?
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let ifa = current {
            let name = String(cString: ifa.pointee.ifa_name)
            let family = ifa.pointee.ifa_addr.pointee.sa_family

            if name == "en0" && family == UInt8(AF_INET) {
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
                    address = String(decoding: hostname.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
                break
            }
            current = ifa.pointee.ifa_next
        }

        return address
    }
}
