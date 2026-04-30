import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    let controller: StatusBarController

    @Environment(\.dismiss) private var dismiss

    @State private var controllerURL = ""
    @State private var apiKey = ""
    @State private var allowSelfSigned = false
    @State private var isEditingCredentials = false
    @State private var compactMode = false
    @State private var pollInterval: Int = 30
    @State private var launchAtLogin = false
    @State private var launchAtLoginInitialized = false
    @State private var isLoading = true
    @State private var isSaving = false
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
                    DiagnosticsSection(controller: controller)
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
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    guard launchAtLoginInitialized else { return }
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
        controllerURL = controller.preferences.cachedURL ?? ""
        apiKey = controller.preferences.cachedAPIKey ?? ""
        allowSelfSigned = controller.preferences.allowSelfSignedCerts
        compactMode = controller.preferences.compactMode
        pollInterval = controller.preferences.pollIntervalSeconds
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchAtLoginInitialized = true
        isLoading = false
    }

    private func revertCredentials() {
        controllerURL = controller.preferences.cachedURL ?? ""
        apiKey = controller.preferences.cachedAPIKey ?? ""
        allowSelfSigned = controller.preferences.allowSelfSignedCerts
        isEditingCredentials = false
        errorMessage = nil
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let result = URLValidator.normalizeAndValidate(controllerURL)
        guard case .success(let url) = result else {
            if case .failure(let error) = result {
                errorMessage = error.errorDescription
            }
            return
        }

        let urlString = url.absoluteString

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
            await controller.reconfigure()
            isEditingCredentials = false
        } catch let error as UniFiError {
            switch error {
            case .httpError(let code) where code == 401 || code == 403:
                errorMessage = "Authentication failed. Check your API key."
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

    private func reset() async {
        await controller.preferences.resetAll()
        controller.resetState()
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
            launchAtLoginInitialized = false
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginInitialized = true
        }
    }
}

// MARK: - Diagnostics Section

private struct DiagnosticsSection: View {
    let controller: StatusBarController

    @State private var versionTapCount = 0

    var body: some View {
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