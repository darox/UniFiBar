import SwiftUI

struct SetupView: View {
    let controller: StatusBarController
    var makeClient: @MainActor (URL, String, Bool) -> any UniFiClientProtocol = CredentialFlow.makeDefaultClient
    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var isValidating = false
    @State private var errorMessage: String?
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

        let outcome = await CredentialFlow.connect(
            controller: controller,
            urlString: controllerURL,
            apiKey: apiKey,
            allowSelfSigned: allowSelfSigned,
            makeClient: makeClient
        )
        if !Task.isCancelled { isValidating = false }

        switch outcome {
        case .connected:
            dismiss()
        case .cancelled:
            return
        case .urlInvalid(let message):
            errorMessage = message
        case .failed(let error):
            errorMessage = StatusBarController.connectionErrorMessage(for: error)
            // Mirror the controller's auth-throttle deadline in local UI state so the
            // button re-enables when the window opens.
            guard let deadline = controller.connectRetryDeadline else { return }
            retryTask?.cancel()
            retryAvailableAt = deadline
            let remaining = max(0, deadline.timeIntervalSinceNow)
            retryTask = Task {
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                retryAvailableAt = nil
            }
        }
    }
}
