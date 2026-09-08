import Foundation

struct AuditFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw AuditFailure(message) }
}

@main
struct NativeAudit {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count >= 4, args[1] == "--synthetic-native-audit", let id = UUID(uuidString: args[3]) else {
            print("Explicit --synthetic-native-audit <mode> <run UUID> [port/candidate] required")
            exit(2)
        }
        let mode = args[2]
        if mode == "ui" {
            runFixtureUI(id: id, output: URL(fileURLWithPath: args[0]).deletingLastPathComponent())
        }
        Task { @MainActor in
            do {
                if mode.hasPrefix("storage-") {
                    exit(try await storageCheck(mode, id: id, argument: args.count > 4 ? args[4] : nil))
                } else if mode == "ui-cleanup" {
                    try cleanupUIDefaults(id: id)
                } else if mode.hasPrefix("transport-") {
                    let check = String(mode.dropFirst("transport-".count))
                    guard args.count == 5, let port = Int(args[4]) else { throw AuditFailure("port required") }
                    try await transportCheck(check, port: port, pinByte: check == "mismatch" ? 9 : nil)
                } else { throw AuditFailure("unknown mode") }
                exit(0)
            } catch { print("FAIL: \(error)"); exit(1) }
        }
        dispatchMain()
    }
}
