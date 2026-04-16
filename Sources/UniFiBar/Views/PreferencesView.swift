import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    let controller: StatusBarController
    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var isEditingCredentials = false
    @State private var compactMode = true
    @State private var pollInterval: Int = 30
    @State private var launchAtLogin = false
    @State private var versionTapCount = 0
    @State private var isLoading = true
    @State private var showResetConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    connectionSection
                    siteSection
                    behaviorSection
                    visibilitySection
                    diagnosticsSection
                    resetSection
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 480)
        .task { await loadExisting() }
        .confirmationDialog("Reset UniFiBar?", isPresented: $showResetConfirmation) {
            Button("Reset & Forget", role: .destructive) {
                Task { await reset() }
            }
        } message: {
            Text("This will remove all saved credentials and settings. You will need to set up again.")
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            if isEditingCredentials {
                TextField("Controller URL", text: $controllerURL, prompt: Text("https://192.168.1.1"))
                SecureField("API Key", text: $apiKey, prompt: Text("Paste your API key"))
                Toggle("Allow self-signed certificates", isOn: $allowSelfSigned)
                HStack {
                    Button("Cancel") {
                        revertCredentials()
                    }
                    Spacer()
                    Button("Update") {
                        Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controllerURL.isEmpty || apiKey.isEmpty)
                }
            } else {
                LabeledContent("Controller URL", value: controllerURL)
                LabeledContent("API Key") {
                    Button("Change\u{2026}") {
                        apiKey = ""
                        isEditingCredentials = true
                    }
                    .buttonStyle(.borderless)
                }
                LabeledContent("Self-signed certificates") {
                    Text(allowSelfSigned ? "Allowed" : "Blocked")
                }
                Button("Edit Connection\u{2026}") {
                    isEditingCredentials = true
                }
                if allowSelfSigned {
                    Button("Reset Certificate Pin") {
                        Task {
                            await controller.resetCertPin()
                        }
                    }
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var siteSection: some View {
        Group {
            if let siteId = controller.preferences.siteId {
                Section {
                    LabeledContent("Site ID", value: siteId)
                } header: {
                    Text("Site")
                }
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        Section {
            Toggle("Compact mode", isOn: $compactMode)
                .onChange(of: compactMode) { _, newValue in
                    controller.preferences.compactMode = newValue
                    UserDefaults.standard.set(newValue, forKey: "com.unifbar.compactMode")
                }
            Picker("Poll interval", selection: $pollInterval) {
                Text("10s").tag(10)
                Text("15s").tag(15)
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("120s").tag(120)
                Text("300s").tag(300)
            }
            .onChange(of: pollInterval) { _, newValue in
                controller.preferences.setPollInterval(newValue)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
        } header: {
            Text("Behavior")
        }
    }

    // MARK: - Visibility

    private var visibilitySection: some View {
        Section {
            ForEach(MenuSection.allCases, id: \.rawValue) { section in
                SectionToggleRow(section: section, preferences: controller.preferences)
            }
        } header: {
            Text("Visible Sections")
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            let log = controller.diagnosticsLog
            let events = log.recentEvents

            LabeledContent("Version") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("v\(controller.updateChecker.currentVersion)")
                        .onTapGesture {
                            versionTapCount += 1
                            if versionTapCount >= 5 {
                                versionTapCount = 0
                                controller.updateChecker.toggleDebugUpdate()
                            }
                        }
                    if controller.updateChecker.updateAvailable, let latest = controller.updateChecker.latestVersion {
                        Button("v\(latest) available") {
                            if controller.updateChecker.releaseURL != nil {
                                NSWorkspace.shared.open(controller.updateChecker.releaseURL!)
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                    }
                }
            }

            LabeledContent("Consecutive Errors") {
                Text("\(controller.consecutiveErrorCount)")
            }
            LabeledContent("Poll Interval") {
                Text("\(controller.currentPollInterval)s")
            }

            if !events.isEmpty {
                DisclosureGroup("Events (\(events.count))") {
                    ForEach(events.prefix(20)) { event in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(event.level == .error ? Color.red : event.level == .warning ? Color.orange : Color.green)
                                .frame(width: 6, height: 6)
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.message)
                                    .font(.caption)
                                    .lineLimit(1)
                                if let detail = event.detail {
                                    Text(detail)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }

            HStack {
                Button("Copy Report") {
                    let report = log.exportText(
                        errorState: controller.wifiStatus.errorState,
                        consecutiveErrors: controller.consecutiveErrorCount,
                        pollInterval: controller.currentPollInterval,
                        controllerHost: controller.preferences.controllerURL?.host,
                        allowSelfSignedCerts: controller.preferences.allowSelfSignedCerts,
                        wifiStatus: controller.wifiStatus
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                Spacer()
                Button("Clear Log") {
                    log.clear()
                }
            }
        } header: {
            Text("Diagnostics")
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button("Reset & Forget All Settings\u{2026}", role: .destructive) {
                showResetConfirmation = true
            }
        } footer: {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("UniFiBar v\(version)")
            }
        }
    }

    // MARK: - Actions

    /// Load credentials from Keychain (first load only).
    private func loadExisting() async {
        await controller.preferences.checkConfiguration()
        controllerURL = controller.preferences.cachedURL ?? ""
        apiKey = controller.preferences.cachedAPIKey ?? ""
        allowSelfSigned = controller.preferences.allowSelfSignedCerts
        compactMode = controller.preferences.compactMode
        pollInterval = controller.preferences.pollIntervalSeconds
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isLoading = false
    }

    /// Revert to cached values without touching Keychain.
    private func revertCredentials() {
        controllerURL = controller.preferences.cachedURL ?? ""
        apiKey = controller.preferences.cachedAPIKey ?? ""
        allowSelfSigned = controller.preferences.allowSelfSignedCerts
        isEditingCredentials = false
        errorMessage = nil
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
              let host = url.host(), !host.isEmpty,
              url.query == nil, url.fragment == nil
        else {
            errorMessage = "Invalid URL. Use HTTPS format: https://192.168.1.1"
            return
        }
        _ = url

        do {
            try await controller.preferences.save(
                controllerURL: urlString,
                apiKey: trimmedKey,
                allowSelfSigned: allowSelfSigned
            )
            await controller.reconfigure()
            isEditingCredentials = false
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
        .onChange(of: isEnabled) { _, newValue in
            preferences.setSectionEnabled(section, enabled: newValue)
        }
    }
}