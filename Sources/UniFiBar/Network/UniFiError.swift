import Foundation

enum UniFiError: Error, Sendable {
    case httpError(statusCode: Int)
    case noSitesFound
    case selfNotFound
    case invalidURL
    case notConfigured
}
