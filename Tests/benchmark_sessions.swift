// Compile with Models/*.swift and Utils/Formatters.swift using swiftc -O -swift-version 6.
// Synthetic model microbenchmark only: no app launch, controller or native credentials.
import Foundation

@main
struct SessionBenchmark {
    @MainActor static func main() {
        let devices = (0..<500).map { index in
            DeviceDTO(id: "\(index)", macAddress: "AA:BB:\(index)", name: "AP \(index)",
                      model: nil, state: "ONLINE", firmwareUpdatable: nil, features: nil,
                      firmwareVersion: nil, ipAddress: nil)
        }
        let sessions = (0..<1000).map { index in
            SessionDTO(mac: "fixture", apMac: "aa:bb:\(index % 500)", duration: 60, assocTime: nil)
        }
        let status = WiFiStatus()
        for _ in 0..<10 { status.updateSessions(sessions, devices: devices) }
        var samples: [Double] = []
        for _ in 0..<7 {
            let start = ContinuousClock.now
            for _ in 0..<50 { status.updateSessions(sessions, devices: devices) }
            let elapsed = start.duration(to: .now).components
            samples.append((Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * 1000 / 50)
        }
        precondition(status.sessions?.count == 500)
        precondition(status.sessions?.allSatisfy { $0.duration == 120 && $0.fraction == 1 } == true)
        print("Session aggregation: 1,000 sessions / 500 devices; 7 x 50 updates, 10 warmups")
        print("Round means (ms/update):", samples.map { String(format: "%.3f", $0) }.joined(separator: ", "))
        print(String(format: "Median: %.3f ms/update", samples.sorted()[3]))
    }
}
