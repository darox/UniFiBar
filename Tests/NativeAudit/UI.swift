import AppKit
import ApplicationServices
import SwiftUI

@MainActor
func runFixtureUI(id: UUID, output: URL) -> Never {
    NSApplication.shared.setActivationPolicy(.accessory)
    // Process-local AX mode, not a change to permission or system VoiceOver settings.
    NSApplication.shared.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
    Task { @MainActor in
        do { try await uiCheck(id: id, output: output); exit(0) } catch { print("FAIL: \(error)"); exit(1) }
    }
    NSApplication.shared.run()
    exit(2)
}

// Own-process AppKit only. Forms inject client/login-item/clipboard dependencies;
// no app activation, system input, real controller, native Keychain or clipboard.
@MainActor
func uiCheck(id: UUID, output: URL) async throws {
    print("EXTERNAL_AX_TRUSTED=\(AXIsProcessTrusted()); no prompt requested")
    print("SCREENS=\(NSScreen.screens.map { $0.visibleFrame.size }) (read-only; no display changes)")
    let suite = "com.unifibar.native-audit.\(id.uuidString).ui"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let noNative = KeychainHelper(operations: .init(read: { _ in (errSecParam, nil) },
        update: { _, _ in errSecParam }, add: { _ in errSecParam }, delete: { _ in errSecParam }))
    let prefs = PreferencesManager(defaults: defaults, keychain: noNative, removePins: {}, unregisterLoginItem: {})
    let controller = StatusBarController(fixturePreferences: prefs, clientLoader: { nil })
    var copies: [String] = []
    let marker = "SYNTHETIC-PRIVATE-MARKER"
    controller.diagnosticsLog.record(.connection, level: .error, message: marker)
    controller.wifiStatus.essid = marker
    var windows: [NSWindow] = []
    defer { windows.forEach { $0.close() }; controller.tearDown() }

    func host<V: View>(_ view: V, width: CGFloat, name: String) async throws -> NSHostingView<V> {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        try require(size.width <= 480 && size.height <= 1600 && size.height > 0, "bounded fixture render \(name): \(size)")
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: size.height)),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "UniFiBar Synthetic Audit"
        window.isReleasedWhenClosed = false
        window.contentView = host
        windows.append(window)
        window.orderBack(nil) // Fixture window only; never activate or steal keyboard focus.
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Yield to SwiftUI/AppKit to install the real accessibility tree (bounded below).
        for _ in 0..<20 {
            if elements(host).contains(where: { ["Refresh", "Copy Report", "Connect"].contains(axLabel($0) ?? "") }) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try capture(host, name: name)
        print("UI \(name) fitting=\(size) rendered=\(host.bounds.size)")
        return host
    }
    func capture(_ host: NSView, name: String) throws {
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw AuditFailure("bitmap \(name)") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw AuditFailure("PNG \(name)") }
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
    func element(_ root: Any, label: String) throws -> AnyObject {
        guard let found = elements(root).first(where: { axLabel($0) == label }) else {
            throw AuditFailure("missing AX label '\(label)'; available=\(elements(root).map { axLabel($0) ?? "?" })")
        }
        return found
    }
    func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<40 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        try require(condition(), message)
    }
    func hasText(_ root: NSView, _ text: String) -> Bool {
        elements(root).contains { node in
            if axLabel(node) == text { return true }
            guard node.accessibilityRole?() == .staticText else { return false }
            let value: String? = node.accessibilityValue?()
            return value == text
        }
    }
    func enter(_ value: String, in root: NSView, label: String) throws {
        try require(try element(root, label: label).accessibilityRole?() == .textField, "owned AX text field \(label)")
        // SwiftUI's AX wrapper does not propagate setAccessibilityValue to its binding.
        let fields = descendants(root).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        let matches = fields.filter { ($0 is NSSecureTextField) == (label == "API Key") }
        guard matches.count == 1, let field = matches.first else {
            throw AuditFailure("unique native field \(label)")
        }
        field.stringValue = value
        try require(field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field)) != nil,
            "owned field binding notification \(label)")
    }
    // Menu setup/loading/error use real content, but openWindow/reset/quit are not pressed.
    for state in ["setup", "loading", "error", "connected-full", "connected-compact", "connected-tall", "connected-empty", "connected-unavailable"] {
        prefs.isConfigured = state != "setup"
        prefs.compactMode = state == "connected-compact"
        controller.wifiStatus.clearState()
        if state == "error" { controller.wifiStatus.markError(.invalidAPIKey(httpCode: 401)) }
        if state.hasPrefix("connected") {
            controller.wifiStatus.isConnected = true
            controller.wifiStatus.essid = String(repeating: marker + "-", count: 10)
            controller.wifiStatus.apName = "Synthetic AP"
            controller.wifiStatus.beginSupplementalRefresh()
            controller.wifiStatus.updateDevices(nil)
            if ["connected-full", "connected-compact", "connected-tall"].contains(state) {
                controller.wifiStatus.vpnTunnels = (0..<30).map { VPNTunnelDTO(name: "Synthetic long tunnel \($0)", status: nil) }
                controller.wifiStatus.dataAvailability[.vpn] = .available
            }
            if state == "connected-empty" {
                controller.wifiStatus.updateDevices([])
                controller.wifiStatus.updateVPN([])
            }
        }
        let root = MenuContentView(controller: controller, copyReport: { copies.append($0) }, availableHeight: state == "connected-tall" ? 900 : 360)
            .frame(width: 320).background(Color(nsColor: .windowBackgroundColor))
        let hosted = try await host(root, width: 320, name: state)
        for label in ["Refresh", "Preferences", "Quit"] {
            let footer = try element(hosted, label: label)
            try require(footer.accessibilityRole?() == .button, "footer AX role \(label)")
            guard let frame = footer.accessibilityFrame?() else { throw AuditFailure("footer frame") }
            let viewport = hosted.window!.convertToScreen(hosted.convert(hosted.bounds, to: nil))
            try require(frame.width > 0 && frame.height > 0 && viewport.insetBy(dx: -1, dy: -1).contains(frame), "footer visible \(state)/\(label)")
            print("FOOTER \(state) \(label) frame=\(frame)")
        }
        if state == "error" {
            try require(try element(hosted, label: "Copy Diagnostics").accessibilityPerformPress?() == true, "menu diagnostic AX press")
            try require(copies.count == 1 && !copies[0].contains(marker), "menu copy redacts into fixture sink")
        }
        if state.hasPrefix("connected") {
            let scroll = descendants(hosted).compactMap { $0 as? NSScrollView }.first
            if let scroll, let document = scroll.documentView {
                print("SCROLL \(state) viewport=\(scroll.contentSize) document=\(document.frame.size)")
                document.scroll(NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentSize.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                hosted.layoutSubtreeIfNeeded()
                try capture(hosted, name: state + "-scrolled")
            } else { print("UNVERIFIED: SwiftUI scroll view not exposed as NSScrollView") }
        }
        hosted.window?.close()
    }
    // First exercise the existing diagnostic section independently of form state.
    let diagnostics = try await host(Form {
        DiagnosticsSection(controller: controller, copyReport: { copies.append($0) })
    }.formStyle(.grouped).frame(width: 480, height: 600), width: 480, name: "diagnostics")
    let copy = try element(diagnostics, label: "Copy Report")
    try require(copy.accessibilityPerformPress?() == true, "default diagnostic copy press")
    try require(copies.count == 2 && !copies.last!.contains(marker), "default diagnostic redaction")
    let toggle = try element(diagnostics, label: "Include private details in copied report")
    guard let toggleControl = toggle as? NSSwitch else { throw AuditFailure("private opt-in native switch") }
    try require(toggleControl.isEnabled && toggleControl.state == .off, "private details off by default")
    let focused = diagnostics.window!.makeFirstResponder(toggleControl)
    if focused { try require(diagnostics.window!.firstResponder === toggleControl, "owned native focus target") }
    print("PROGRAMMATIC_SWITCH_FOCUS=\(focused); no global keyboard events or window activation")
    toggleControl.performClick(nil) // Owned AppKit control action, not global pointer/keyboard input.
    // Wait for state rendering, not external focus/permission changes.
    for _ in 0..<20 {
        if toggleControl.state == .on { break }
        try await Task.sleep(for: .milliseconds(25))
    }
    try require(copy.accessibilityPerformPress?() == true, "private diagnostic copy press")
    try require(copies.count == 3 && copies.last!.contains(marker), "explicit private copy")
    try require(copy.accessibilityPerformPress?() == true, "subsequent diagnostic copy press")
    try require(copies.count == 4 && !copies.last!.contains(marker), "one-copy opt-in resets")
    @MainActor final class LoginFixture {
        var enabled = true
        var writes: [Bool] = []
        func set(_ enabled: Bool) throws {
            writes.append(enabled)
            if enabled { throw AuditFailure("synthetic login-item failure") }
            self.enabled = enabled
        }
    }
    let fakeLogin = LoginFixture()
    var clientInputs: [(URL, String, Bool)] = []
    var formFailure: any Error = UniFiError.httpError(statusCode: 401)
    let rejectClient: @MainActor (URL, String, Bool) -> any UniFiClientProtocol = { url, key, selfSigned in
        clientInputs.append((url, key, selfSigned))
        let error = formFailure
        return UniFiClient(fixtureTransport: { _ in throw error })
    }
    let preferences = try await host(PreferencesView(controller: controller, makeClient: rejectClient,
        loginItemIsEnabled: { fakeLogin.enabled }, setLoginItemEnabled: fakeLogin.set,
        copyReport: { copies.append($0) }).frame(height: 900), width: 480, name: "preferences")
    print("PREFERENCES_INITIAL_LOGIN_WRITES=\(fakeLogin.writes)")
    try require(fakeLogin.writes.isEmpty, "opening Preferences must not register an already enabled login item")
    try require(clientInputs.isEmpty, "opening Preferences must not create a client")
    guard let login = try element(preferences, label: "Launch at login") as? NSSwitch,
          let compact = try element(preferences, label: "Compact mode") as? NSSwitch else {
        throw AuditFailure("owned preference switches")
    }
    try require(login.state == .on && compact.state == .off, "loaded preference switch state")
    // The system can become not-enabled while still registered/requiring approval.
    // An intentional OFF action must still reach unregister through the setter.
    fakeLogin.enabled = false
    login.performClick(nil)
    try await waitFor("fake login item disabled") { fakeLogin.writes == [false] && !fakeLogin.enabled }
    login.performClick(nil)
    try await waitFor("failed login toggle restores observed state") { fakeLogin.writes.count >= 2 && login.state == .off }
    print("PREFERENCES_FAILED_LOGIN_WRITES=\(fakeLogin.writes)")
    try require(fakeLogin.writes == [false, true], "failed login rollback must not invoke another login-item operation")
    compact.performClick(nil)
    try await waitFor("compact preference persists") { prefs.compactMode && defaults.bool(forKey: "com.unifbar.compactMode") }
    let fullCopy = try element(preferences, label: "Copy Report")
    try require(fullCopy.accessibilityPerformPress?() == true && copies.count == 5 && !copies.last!.contains(marker),
        "full Preferences default copy uses injected sink")

    // Shared bounded form checks exercise the actual bindings and public connect flow.
    func checkForm(_ root: NSView, button label: String, name: String) async throws {
        formFailure = UniFiError.httpError(statusCode: 401)
        let button = try element(root, label: label)
        try require(button.isAccessibilityEnabled?() == false, "empty \(name) submit disabled")
        let before = clientInputs.count
        try enter("http://controller.invalid", in: root, label: "Controller URL")
        try enter("  synthetic-form-key  ", in: root, label: "API Key")
        try await waitFor("\(name) submit enabled") { button.isAccessibilityEnabled?() == true }
        try require(button.accessibilityPerformPress?() == true, "\(name) invalid submit")
        try await waitFor("\(name) invalid URL visible") { hasText(root, "Only HTTPS URLs are allowed.") }
        try require(clientInputs.count == before, "\(name) rejects invalid URL before client creation")
        try enter("https://controller.invalid/", in: root, label: "Controller URL")
        let trust = try element(root, label: "Allow self-signed certificates")
        if let control = trust as? NSSwitch { control.performClick(nil) } else { try require(trust.accessibilityPerformPress?() == true, "\(name) self-signed toggle") }
        try require(button.accessibilityPerformPress?() == true, "\(name) synthetic submit")
        try await waitFor("\(name) authentication error visible") { hasText(root, "Authentication failed. Check your API key.") }
        try require(clientInputs.count == before + 1, "\(name) creates one injected client")
        let input = clientInputs.last!
        try require(input.0.absoluteString == "https://controller.invalid" && input.1 == "synthetic-form-key" && input.2,
            "\(name) normalized URL, trimmed key and trust choice reach injected factory")
        try require(!prefs.isConfigured && prefs.cachedAPIKey == nil, "rejected validation cannot configure \(name)")
        for failure in [CertificateConnectionError.nameMismatch, .pinStorageFailed] {
            formFailure = failure
            try require(button.accessibilityPerformPress?() == true, "\(name) retry certificate failure")
            try await waitFor("\(name) displays the certificate failure, not generic reachability") {
                hasText(root, failure.localizedDescription)
            }
        }
        try capture(root, name: name + "-error")
        print("PASS: \(name) empty/invalid URL/synthetic auth error; real bindings and actions, offline factory")
    }
    try await checkForm(preferences, button: "Update", name: "preferences")
    preferences.window?.close()
    // Opaque backing matches the real window; without it the offscreen capture
    // cannot composite the Liquid Glass button material (labels vanish).
    let setup = try await host(SetupView(controller: controller, makeClient: rejectClient)
        .background(Color(nsColor: .windowBackgroundColor)), width: 420, name: "setup-form")
    try await checkForm(setup, button: "Connect", name: "setup-form")
    try require(fakeLogin.writes == [false, true], "later form rendering cannot repeat login-item actions")
    try require(controller.pollTask == nil && !controller.hasSystemObservers, "fixture never starts polling/observers")
    // Real native trust dialog; only synthetic identity and this process's own buttons.
    for title in ["Cancel", "Trust Certificate"] {
        var pressed = false
        var attempts = 0
        let timer = Timer(timeInterval: 0.025, repeats: true) { _ in
            MainActor.assumeIsolated {
                attempts += 1
                if let view = NSApp.modalWindow?.contentView,
                   let button = descendants(view).compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) {
                    pressed = true
                    button.performClick(nil)
                } else if attempts >= 80 {
                    NSApp.abortModal()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let accepted = await confirmControllerCertificate(.init(host: "controller.invalid",
            fingerprint: Array(repeating: "AB", count: 32).joined(separator: ":")))
        timer.invalidate()
        try require(pressed && accepted == (title == "Trust Certificate"), "native certificate prompt \(title)")
    }
    print("PASS: native certificate prompt cancel/approve; synthetic identity only")
    try cleanupUIDefaults(id: id)
    print("PASS: native menu/diagnostics/Setup/Preferences actions; synthetic dependencies only; owned windows close on return")
}

// Also callable by the runner after a timeout, when this process's defer cannot run.
func cleanupUIDefaults(id: UUID) throws {
    let suite = "com.unifibar.native-audit.\(id.uuidString).ui"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    try require(defaults.synchronize() && defaults.persistentDomain(forName: suite)?.isEmpty != false, "UI defaults cleanup")
    print("UI_DEFAULTS_CLEANUP=true")
}

@MainActor private func descendants(_ root: NSView) -> [NSView] {
    [root] + root.subviews.flatMap(descendants)
}
@MainActor private func axLabel(_ node: AnyObject) -> String? {
    if let label = node.accessibilityLabel?() ?? node.accessibilityTitle?() { return label }
    // Native Form controls associate their visible label through a title element.
    let title = node.accessibilityTitleUIElement?() as AnyObject?
    let value: String? = title?.accessibilityValue?()
    return value
}
@MainActor private func elements(_ root: Any, depth: Int = 0) -> [AnyObject] {
    if depth == 0, let view = root as? NSView, let window = view.window {
        // Traverse through the parent window, like an AX client: asking an ignored
        // NSHostingView directly does not populate SwiftUI's accessibility subtree.
        return elements(window, depth: 1)
    }
    guard depth < 30 else { return [] }
    // SwiftUI AccessibilityNode implements the ObjC selectors but does not declare
    // NSAccessibilityProtocol conformance. Conditional selector dispatch is required.
    let node = root as AnyObject
    let children = (node.accessibilityChildren?() ?? nil) ?? []
    return [node] + children.flatMap { elements($0, depth: depth + 1) }
}
