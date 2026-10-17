import Foundation

/// The connect flow shared by the setup sheet and the preferences window. The controller owns
/// throttling and validation; this helper removes the duplicated trim, URL check and client build.
@MainActor
enum CredentialFlow {
    static func makeDefaultClient(url: URL, apiKey: String, allowSelfSigned: Bool) -> any UniFiClientProtocol {
        UniFiClient(baseURL: url, apiKey: apiKey, allowSelfSigned: allowSelfSigned,
                    confirmCertificate: confirmControllerCertificate)
    }

    /// Each caller presents the failure its own way, so the outcome stays explicit.
    enum Outcome {
        case connected
        case cancelled
        case urlInvalid(String)
        case failed(Error)
    }

    static func connect(
        controller: StatusBarController,
        urlString: String,
        apiKey: String,
        allowSelfSigned: Bool,
        makeClient: (URL, String, Bool) -> any UniFiClientProtocol
    ) async -> Outcome {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        switch URLValidator.normalizeAndValidate(urlString) {
        case .success(let valid):
            url = valid
        case .failure(let error):
            return .urlInvalid(error.errorDescription ?? "Invalid controller URL or API key.")
        }

        do {
            try await controller.connect(using: makeClient(url, trimmedKey, allowSelfSigned),
                                         url: url, apiKey: trimmedKey, allowSelfSigned: allowSelfSigned)
            return Task.isCancelled ? .cancelled : .connected
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error)
        }
    }
}
