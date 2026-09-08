import Foundation

enum URLValidator {
    enum ValidationError: Error, LocalizedError {
        case invalidFormat
        case mustBeHTTPS
        case emptyHost
        case noQueryOrFragment
        case noUserinfo

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Invalid URL. Use HTTPS format: https://192.168.1.1"
            case .mustBeHTTPS: return "Only HTTPS URLs are allowed."
            case .emptyHost: return "URL must include a hostname."
            case .noQueryOrFragment: return "URL must not contain query parameters or fragments."
            case .noUserinfo: return "URL must not contain user credentials (user:pass@)."
            }
        }
    }

    static func normalizeAndValidate(_ raw: String) -> Result<URL, ValidationError> {
        var urlString = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }
        while urlString.hasSuffix("/") {
            urlString.removeLast()
        }
        guard let url = URL(string: urlString) else {
            return .failure(.invalidFormat)
        }
        guard url.scheme?.lowercased() == "https" else {
            return .failure(.mustBeHTTPS)
        }
        guard let host = url.host(), !host.isEmpty else {
            return .failure(.emptyHost)
        }
        if let port = url.port, !(1...65535).contains(port) {
            return .failure(.invalidFormat)
        }
        guard url.query == nil, url.fragment == nil else {
            return .failure(.noQueryOrFragment)
        }
        guard url.user == nil else {
            return .failure(.noUserinfo)
        }
        return .success(url)
    }
}
