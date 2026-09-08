import AppKit

/// Used only by user-initiated setup/preferences connections, never background polling.
@MainActor
func confirmControllerCertificate(_ certificate: PinnedCertDelegate.CertificateDetails) async -> Bool {
    guard !Task.isCancelled else { return false }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Trust this controller certificate?"
    alert.informativeText = """
        The certificate does not match the controller address. UniFi factory certificates often name unifi.local instead of the IP address.

        Controller: \(certificate.host)
        Certificate SHA-256:
        \(certificate.fingerprint)

        Verify this fingerprint through a trusted connection before continuing. Trusting saves the certificate's public key for this address. Expired certificates and changed keys will still be blocked.
        """
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Trust Certificate")
    let response = alert.runModal()
    return response == .alertSecondButtonReturn && !Task.isCancelled
}
