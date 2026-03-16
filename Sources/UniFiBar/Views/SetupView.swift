import SwiftUI

struct SetupView: View {
    let controller: StatusBarController
    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var isValidating = false
    @State private var errorMessage: String?

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
                .disabled(controllerURL.isEmpty || apiKey.isEmpty || isValidating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func validate() async {
        isValidating = true
        errorMessage = nil

        var urlString = controllerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http") {
            urlString = "https://" + urlString
        }
        while urlString.hasSuffix("/") {
            urlString.removeLast()
        }

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL format."
            isValidating = false
            return
        }

        let testClient = UniFiClient(
            baseURL: url,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            allowSelfSigned: allowSelfSigned
        )

        do {
            let siteId = try await testClient.fetchSiteId()
            try await controller.preferences.save(
                controllerURL: urlString,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                allowSelfSigned: allowSelfSigned
            )
            controller.preferences.siteId = siteId
            await controller.reconfigure()
            dismiss()
        } catch let error as UniFiError {
            switch error {
            case .httpError(let code) where code == 401 || code == 403:
                errorMessage = "Invalid API key. Check your key and try again."
            case .noSitesFound:
                errorMessage = "Connected, but no sites found on this controller."
            default:
                errorMessage = "Could not connect to controller. Check the URL."
            }
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
        }

        isValidating = false
    }
}
