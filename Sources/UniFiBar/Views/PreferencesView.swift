import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    let controller: StatusBarController
    var makeClient: @MainActor (URL, String, Bool) -> any UniFiClientProtocol = CredentialFlow.makeDefaultClient
    var loginItemIsEnabled: @MainActor () -> Bool = { SMAppService.mainApp.status == .enabled }
    var setLoginItemEnabled: @MainActor (Bool) throws -> Void = { enabled in
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
    var copyReport: @MainActor (String) -> Void = DiagnosticsLog.copyToClipboard

    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var isEditingCredentials = false
    @State private var compactMode = false
    @State private var pollInterval: Int = 30
    @State private var launchAtLogin = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var connectionTask: Task<Void, Never>?
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
                    DiagnosticsSection(controller: controller, copyReport: copyReport)
                    resetSection
                }
                .formStyle(.grouped)
                .disabled(controller.preferences.isResetting)
            }
        }
        .frame(width: 480)
        .task { await loadExisting() }
        .onDisappear {
            connectionTask?.cancel()
            isSaving = false
        }
        .confirmationDialog("Reset UniFiBar?", isPresented: $showResetConfirmation) {
            Button("Reset & Forget", role: .destructive) {
                connectionTask?.cancel()
                let cleanup = controller.resetConfiguration()
                Task { await reset(cleanup) }
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
                        connectionTask?.cancel()
                        connectionTask = Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controllerURL.isEmpty || apiKey.isEmpty || isSaving)
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
            if let errorMessage = errorMessage ?? controller.preferences.credentialError {
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
                    controller.preferences.setCompactMode(newValue)
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
                controller.restartPolling()
            }
            // The closure literal avoids a reabstraction thunk for the method reference.
            // Swift 6.3.3 (Xcode 26.6) crashes in IRGen on that thunk. See issue #33.
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in setLaunchAtLogin(newValue) }
            ))
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

    private func loadExisting() async {
        await controller.preferences.checkConfiguration()
        guard !Task.isCancelled else { return }
        controllerURL = controller.preferences.cachedURL ?? ""
        apiKey = controller.preferences.cachedAPIKey ?? ""
        allowSelfSigned = controller.preferences.allowSelfSignedCerts
        compactMode = controller.preferences.compactMode
        pollInterval = controller.preferences.pollIntervalSeconds
        launchAtLogin = loginItemIsEnabled()
        isLoading = false
        isEditingCredentials = !controller.preferences.isConfigured
    }

    private func revertCredentials() {
        connectionTask?.cancel()
        isSaving = false
        controllerURL = controller.preferences.cachedURL ?? ""
        apiKey = controller.preferences.cachedAPIKey ?? ""
        allowSelfSigned = controller.preferences.allowSelfSignedCerts
        isEditingCredentials = false
        errorMessage = nil
    }

    private func save() async {
        guard !Task.isCancelled else { return }
        errorMessage = nil
        isSaving = true
        defer { if !Task.isCancelled { isSaving = false } }

        let outcome = await CredentialFlow.connect(
            controller: controller,
            urlString: controllerURL,
            apiKey: apiKey,
            allowSelfSigned: allowSelfSigned,
            makeClient: makeClient
        )

        switch outcome {
        case .connected:
            isEditingCredentials = false
        case .cancelled:
            return
        case .urlInvalid(let message):
            errorMessage = message
        case .failed(let error):
            errorMessage = StatusBarController.connectionErrorMessage(for: error)
        }
    }

    private func reset(_ cleanup: Task<Void, Error>) async {
        do {
            try await cleanup.value
            dismiss()
        } catch {
            controllerURL = ""
            apiKey = ""
            allowSelfSigned = false
            isSaving = false
            isEditingCredentials = true
            errorMessage = controller.preferences.credentialError
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // Only the control's binding invokes operations; loading/rollback just update state.
        launchAtLogin = enabled
        do {
            try setLoginItemEnabled(enabled)
        } catch {
            launchAtLogin = loginItemIsEnabled()
        }
    }
}

// MARK: - Diagnostics Section

struct DiagnosticsSection: View {
    let controller: StatusBarController
    var copyReport: @MainActor (String) -> Void = DiagnosticsLog.copyToClipboard

    @State private var versionTapCount = 0
    @State private var includePrivateDetails = false

    var body: some View {
        Section {
            let log = controller.diagnosticsLog
            let events = log.recentEvents(limit: DisplayLimits.rows)

            LabeledContent("Version") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("v\(controller.updateChecker.currentVersion)")
                        .onTapGesture {
                            #if DEBUG
                            versionTapCount += 1
                            if versionTapCount >= 5 {
                                versionTapCount = 0
                                controller.updateChecker.toggleDebugUpdate()
                            }
                            #endif
                        }
                    if controller.updateChecker.updateAvailable, let latest = controller.updateChecker.latestVersion {
                        Button("v\(latest) available") {
                            if let url = controller.updateChecker.releaseURL {
                                NSWorkspace.shared.open(url)
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

            #if DEBUG
            LabeledContent("Debug Mode") {
                Toggle(isOn: Binding(
                    get: { controller.updateChecker.isDebugMode },
                    set: { _ in controller.updateChecker.toggleDebugUpdate() }
                )) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Debug Mode")
            }
            #endif

            if !events.isEmpty {
                DisclosureGroup("Events (\(events.count))") {
                    ForEach(events) { event in
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

            Toggle("Include private details in copied report", isOn: $includePrivateDetails)
                .accessibilityLabel("Include private details in copied report")
            Text("Includes network identifiers and raw events, which may contain secrets. Review before sharing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Copy Report") {
                    let report = log.exportText(
                        errorState: controller.wifiStatus.errorState,
                        consecutiveErrors: controller.consecutiveErrorCount,
                        pollInterval: controller.currentPollInterval,
                        controllerHost: controller.preferences.controllerURL?.host,
                        allowSelfSignedCerts: controller.preferences.allowSelfSignedCerts,
                        wifiStatus: controller.wifiStatus,
                        includePrivateDetails: includePrivateDetails
                    )
                    copyReport(report)
                    includePrivateDetails = false
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
}

// MARK: - Section Toggle Row

private struct SectionToggleRow: View {
    let section: MenuSection
    let preferences: PreferencesManager

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isSectionEnabled(section) },
            set: { preferences.setSectionEnabled(section, enabled: $0) }
        )) {
            Label(section.displayName, systemImage: section.icon)
        }
    }
}
