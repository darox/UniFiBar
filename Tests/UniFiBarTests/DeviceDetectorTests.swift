import Darwin
import Testing
@testable import UniFiBar

struct DeviceDetectorTests {
    @Test func onlyUpRunningInterfacesAreReturnedInNameOrder() throws {
        let active = UInt32(IFF_UP | IFF_RUNNING)
        let interfaces: [(String, String, UInt32)] = [
            ("en9", "192.0.2.9", active), ("en2", "192.0.2.2", UInt32(IFF_UP)),
            ("en3", "192.0.2.3", UInt32(IFF_RUNNING)), ("utun0", "192.0.2.4", active),
            ("en1", "192.0.2.1", active), ("en0", "192.0.2.1", active),
            ("en4", "169.254.1.1", active)
        ]
        let nodes = UnsafeMutablePointer<ifaddrs>.allocate(capacity: interfaces.count)
        nodes.initialize(repeating: ifaddrs(), count: interfaces.count)
        let addresses = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: interfaces.count)
        addresses.initialize(repeating: sockaddr_in(), count: interfaces.count)
        defer {
            for index in interfaces.indices { free(nodes[index].ifa_name) }
            nodes.deinitialize(count: interfaces.count)
            nodes.deallocate()
            addresses.deinitialize(count: interfaces.count)
            addresses.deallocate()
        }
        for (index, interface) in interfaces.enumerated() {
            addresses[index].sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addresses[index].sin_family = sa_family_t(AF_INET)
            #expect(inet_pton(AF_INET, interface.1, &addresses[index].sin_addr) == 1)
            nodes[index].ifa_name = strdup(interface.0)
            nodes[index].ifa_flags = interface.2
            nodes[index].ifa_addr = UnsafeMutableRawPointer(addresses + index).assumingMemoryBound(to: sockaddr.self)
            nodes[index].ifa_next = index + 1 < interfaces.count ? nodes + index + 1 : nil
        }
        #expect(DeviceDetector.activeIPv4Addresses(startingAt: nodes) == ["192.0.2.1", "192.0.2.9"])
        #expect(DeviceDetector.activeIPv4Addresses(startingAt: nil).isEmpty)
    }
}
