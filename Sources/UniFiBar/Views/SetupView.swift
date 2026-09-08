import SwiftUI

struct SetupView: View {
    let controller: StatusBarController
    var makeClient: @MainActor (URL, String, Bool) -> any UniFiClientProtocol = {
        UniFiClient(baseURL: $0, apiKey: $1, allowSelfSigned: $2, confirmCertificate: confirmControllerCertificate)
    }
    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var failedAttempts = 0
    @State private var retryAvailableAt: Date?
    @State private var retryTask: Task<Void, Never>?
    @State private var connectionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            header
            formFields
            errorMessageView
            actionButtons
        }
        .padding(24)
        .frame(width: 420, height: 480)
        .onDisappear {
            connectionTask?.cancel()
            retryTask?.cancel()
            isValidating = false
        }
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
        if let errorMessage = errorMessage ?? controller.preferences.credentialError {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                connectionTask?.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Connect") {
                connectionTask?.cancel()
                connectionTask = Task { await validate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(controllerURL.isEmpty || apiKey.isEmpty || isValidating || isRateLimited || controller.preferences.isResetting)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var isRateLimited: Bool {
        guard let retryAt = retryAvailableAt else { return false }
        return Date() < retryAt
    }

    private func validate() async {
        guard !Task.isCancelled else { return }
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
        if !Task.isCancelled { isValidating = false }
    }

    private func connectWith(url: URL, apiKey: String) async {
        let testClient = makeClient(url, apiKey, allowSelfSigned)

        do {
            try await controller.connect(using: testClient, url: url, apiKey: apiKey, allowSelfSigned: allowSelfSigned)
            try Task.checkCancellation()
            failedAttempts = 0
            dismiss()
        } catch is CancellationError {
            return
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
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        retryAvailableAt = nil
                    }
                }
            case .httpError(let code):
                errorMessage = "Server returned HTTP \(code). Check your controller URL."
            case .noSitesFound:
                errorMessage = "Connected, but no sites found on this controller."
            default:
                errorMessage = error.errorDescription
            }
        } catch let error as CertificateConnectionError {
            errorMessage = error.errorDescription
        } catch is URLError {
            errorMessage = "Could not reach the controller. Check the URL and your network connection."
        } catch let error as KeychainError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Connection failed. Check your URL and network settings."
        }
    }
}
