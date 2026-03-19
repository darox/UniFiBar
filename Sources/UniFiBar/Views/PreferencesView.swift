import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    let controller: StatusBarController
    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var launchAtLogin = false
    @State private var isLoading = true
    @State private var showResetConfirmation = false
    @State private var errorMessage: String?
    @State private var showSectionSettings = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Preferences")
                .font(.title2)
                .fontWeight(.semibold)

            if isLoading {
                ProgressView()
            } else {
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

                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .font(.callout)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }

                    if let siteId = controller.preferences.siteId {
                        HStack {
                            Text("Site ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(siteId)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                    }

                    Divider()

                    DisclosureGroup("Visible Sections", isExpanded: $showSectionSettings) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(MenuSection.allCases, id: \.rawValue) { section in
                                SectionToggleRow(section: section, preferences: controller.preferences)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.callout)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Reset & Forget", role: .destructive) {
                        showResetConfirmation = true
                    }

                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controllerURL.isEmpty || apiKey.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 380)
        .task { await loadExisting() }
        .confirmationDialog("Reset UniFiBar?", isPresented: $showResetConfirmation) {
            Button("Reset & Forget", role: .destructive) {
                Task { await reset() }
            }
        } message: {
            Text("This will remove all saved credentials and settings. You will need to set up again.")
        }
    }

    private func loadExisting() async {
        if let url = await KeychainHelper.shared.read(.controllerURL) {
            controllerURL = url
        }
        if let key = await KeychainHelper.shared.read(.apiKey) {
            apiKey = key
        }
        allowSelfSigned = controller.preferences.allowSelfSignedCerts
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isLoading = false
    }

    private func save() async {
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
              let scheme = url.scheme, scheme == "https",
              let host = url.host(), !host.isEmpty
        else {
            errorMessage = "Invalid URL. Use HTTPS format: https://192.168.1.1"
            return
        }
        _ = url  // validated

        do {
            try await controller.preferences.save(
                controllerURL: urlString,
                apiKey: trimmedKey,
                allowSelfSigned: allowSelfSigned
            )
            await controller.reconfigure()
            dismiss()
        } catch {
            errorMessage = "Failed to save credentials. Please try again."
        }
    }

    private func reset() async {
        await controller.preferences.resetAll()
        controller.stopPolling()
        dismiss()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Section Toggle Row

private struct SectionToggleRow: View {
    let section: MenuSection
    let preferences: PreferencesManager

    @State private var isEnabled: Bool

    init(section: MenuSection, preferences: PreferencesManager) {
        self.section = section
        self.preferences = preferences
        self._isEnabled = State(initialValue: preferences.isSectionEnabled(section))
    }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            Label(section.displayName, systemImage: section.icon)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
        .onChange(of: isEnabled) { _, newValue in
            preferences.setSectionEnabled(section, enabled: newValue)
        }
    }
}
