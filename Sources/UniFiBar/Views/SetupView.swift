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
    @State private var retryTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            header
            formFields
            errorMessageView
            actionButtons
        }
        .padding(24)
        .frame(width: 420, height: 480)
        .onDisappear { retryTask?.cancel() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.router")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Set Up UniFiBar")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Enter your UniFi controller details to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Controller URL") {
                TextField("https://192.168.1.1", text: $controllerURL)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("API Key") {
                SecureField("Paste your API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Allow self-signed certificates", isOn: $allowSelfSigned)
        }
    }

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var actionButtons: some View {
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

    private var isRateLimited: Bool {
        guard let retryAt = retryAvailableAt else { return false }
        return Date() < retryAt
    }

    private func validate() async {
        isValidating = true
        errorMessage = nil

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let result = URLValidator.normalizeAndValidate(controllerURL)
        switch result {
        case .success(let url):
            await connectWith(url: url, apiKey: trimmedKey)
        case .failure(let error):
            errorMessage = error.errorDescription
        }
        isValidating = false
    }

    private func connectWith(url: URL, apiKey: String) async {
        let urlString = url.absoluteString

        let testClient = UniFiClient(
            baseURL: url,
            apiKey: apiKey,
            allowSelfSigned: allowSelfSigned
        )

        do {
            let siteId = try await testClient.fetchSiteId()
            try await controller.preferences.save(
                controllerURL: urlString,
                apiKey: apiKey,
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

                if failedAttempts >= 5 {
                    let delay = min(pow(2.0, Double(failedAttempts - 4)), 30.0)
                    retryAvailableAt = Date().addingTimeInterval(delay)
                    errorMessage = "Too many failed attempts. Wait \(Int(delay))s before retrying."
                    retryTask = Task {
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
            errorMessage = "Connection failed. Check your URL and network settings."
        }
    }
}