import SwiftUI

struct SetupView: View {
    let controller: StatusBarController
    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var failedAttempts = 0
    @State private var retryAvailableAt: Date?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.router")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Set Up UniFiBar")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your UniFi controller details to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Controller URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://192.168.1.1", text: $controllerURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Paste your API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Allow self-signed certificates", isOn: $allowSelfSigned)
                    .font(.callout)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    Task { await validate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(controllerURL.isEmpty || apiKey.isEmpty || isValidating || isRateLimited)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private var isRateLimited: Bool {
        guard let retryAt = retryAvailableAt else { return false }
        return Date() < retryAt
    }

    private func validate() async {
        isValidating = true
        errorMessage = nil

        var urlString = controllerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !urlString.hasPrefix("http") {
            urlString = "https://" + urlString
        }
        while urlString.hasSuffix("/") {
            urlString.removeLast()
        }

        guard let url = URL(string: urlString),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else {
            errorMessage = "Invalid URL. Use format: https://192.168.1.1"
            isValidating = false
            return
        }

        let testClient = UniFiClient(
            baseURL: url,
            apiKey: trimmedKey,
            allowSelfSigned: allowSelfSigned
        )

        do {
            let siteId = try await testClient.fetchSiteId()
            try await controller.preferences.save(
                controllerURL: urlString,
                apiKey: trimmedKey,
                allowSelfSigned: allowSelfSigned
            )
            controller.preferences.siteId = siteId
            failedAttempts = 0
            await controller.reconfigure()
            dismiss()
        } catch let error as UniFiError {
            switch error {
            case .httpError(let code) where code == 401 || code == 403:
                failedAttempts += 1
                errorMessage = "Authentication failed. Check your API key."

                // Rate limit only on auth failures (possible brute force)
                if failedAttempts >= 5 {
                    let delay = min(pow(2.0, Double(failedAttempts - 4)), 30.0)
                    retryAvailableAt = Date().addingTimeInterval(delay)
                    errorMessage = "Too many failed attempts. Wait \(Int(delay))s before retrying."
                    Task {
                        try? await Task.sleep(for: .seconds(delay))
                        retryAvailableAt = nil
                    }
                }
            case .httpError(let code):
                errorMessage = "Server returned HTTP \(code). Check your controller URL."
            case .noSitesFound:
                errorMessage = "Connected, but no sites found on this controller."
            default:
                errorMessage = "Could not connect. Check your URL and certificate settings."
            }
        } catch is URLError {
            errorMessage = "Could not reach the controller. Check the URL and your network connection."
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }

        isValidating = false
    }
}
