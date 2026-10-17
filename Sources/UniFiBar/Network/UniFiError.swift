import Foundation

enum CertificateConnectionError: Error, Sendable, Equatable, LocalizedError {
    case nameMismatch
    case invalidCertificate
    case changedKey
    case pinStorageFailed

    var errorDescription: String? {
        switch self {
        case .nameMismatch:
            "The controller certificate does not match its address. Edit the connection to review and trust its fingerprint, or use a matching certificate."
        case .invalidCertificate:
            "The controller certificate is expired, not yet valid, or unsuitable for HTTPS. Check the certificate and this Mac's date."
        case .changedKey:
            "The controller certificate key has changed. Verify the change before resetting its certificate pin."
        case .pinStorageFailed:
            "Could not read or save the controller certificate pin in Keychain. No connection was trusted."
        }
    }
}

enum UniFiError: Error, Sendable, Equatable, LocalizedError {
    case httpError(statusCode: Int)
    case noSitesFound
    case selfNotFound
    case invalidURL
    case incompleteResponse
    case ambiguousSite
    case throttled(retryInSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "Server returned HTTP \(code)."
        case .noSitesFound: "No sites found on this controller."
        case .selfNotFound: "This Mac was not found in the selected site's client list."
        case .invalidURL: "Invalid controller URL or site identifier."
        case .incompleteResponse: "Controller returned an incomplete, inconsistent or over-limit collection."
        case .ambiguousSite: "Multiple sites found without a default. UniFiBar requires a default site or a single visible site."
        case .throttled(let seconds): "Too many failed attempts. Wait \(seconds)s before retrying."
        }
    }
}
