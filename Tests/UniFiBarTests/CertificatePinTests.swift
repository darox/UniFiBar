import Foundation
import os
import Security
import Testing
@testable import UniFiBar

struct CertificatePinTests {
    @Test(arguments: [false, true])
    func mismatchedNameRequiresExplicitApproval(approved: Bool) async throws {
        let items = Items()
        let prompts = OSAllocatedUnfairLock(initialState: 0)
        let delegate = PinnedCertDelegate(host: "192.0.2.1", pinStore: items.store, confirmCertificate: { certificate in
            #expect(certificate.host == "192.0.2.1")
            #expect(certificate.fingerprint.split(separator: ":").count == 32)
            prompts.withLock { $0 += 1 }
            return approved
        })
        #expect(try await decision(delegate, host: "192.0.2.1", viaTask: true) == .cancelAuthenticationChallenge)
        #expect(prompts.withLock { $0 } == 0)
        #expect(items.state.withLock { $0.pin } == nil)
        #expect(await delegate.approvePendingCertificate() == approved)
        #expect(prompts.withLock { $0 } == 1)
        #expect(items.state.withLock { $0.pin != nil } == approved)
        if approved {
            #expect(try await decision(delegate, host: "192.0.2.1", viaTask: true) == .useCredential)
            let restarted = PinnedCertDelegate(host: "192.0.2.1", pinStore: items.store)
            #expect(try await decision(restarted, host: "192.0.2.1") == .useCredential)
            #expect(try await decision(restarted, certificate: "replacement", host: "192.0.2.1") == .cancelAuthenticationChallenge)
            #expect(restarted.certChanged)
        } else {
            #expect(delegate.failure == .nameMismatch)
        }
    }

    @Test(arguments: ["expired", "future"])
    func approvalCannotOverrideCertificateValidity(certificate: String) async throws {
        let items = Items()
        let delegate = PinnedCertDelegate(host: "192.0.2.1", pinStore: items.store, confirmCertificate: { _ in
            Issue.record("Invalid certificates must never offer approval")
            return true
        })
        #expect(try await decision(delegate, certificate: certificate, host: "192.0.2.1") == .cancelAuthenticationChallenge)
        #expect(await delegate.approvePendingCertificate() == false)
        #expect(delegate.failure == .invalidCertificate)
        #expect(items.state.withLock { $0.pin } == nil)
    }

    @Test func invalidationWhileApprovalIsPendingCannotPin() async throws {
        let items = Items()
        let entered = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        let delegate = PinnedCertDelegate(host: "192.0.2.1", pinStore: items.store, confirmCertificate: { _ in
            entered.continuation.yield(())
            for await _ in resume.stream { break }
            return true
        })
        #expect(try await decision(delegate, host: "192.0.2.1") == .cancelAuthenticationChallenge)
        let pending = Task { await delegate.approvePendingCertificate() }
        for await _ in entered.stream { break }
        delegate.invalidate()
        resume.continuation.yield(())
        #expect(await pending.value == false)
        #expect(try await decision(delegate, host: "192.0.2.1") == .cancelAuthenticationChallenge)
        #expect(items.state.withLock { $0.pin } == nil)
        entered.continuation.finish()
        resume.continuation.finish()
    }

    @Test(arguments: ["unreadable", "changed", "save-failed"])
    func approvalCannotBypassPinProtection(mode: String) async throws {
        let items = Items()
        if mode == "unreadable" { items.state.withLock { $0.readError = errSecInteractionNotAllowed } }
        if mode == "changed" { items.state.withLock { $0.pin = Data(repeating: 0, count: 32) } }
        if mode == "save-failed" { items.state.withLock { $0.addError = errSecAuthFailed } }
        let original = items.state.withLock { $0.pin }
        let delegate = PinnedCertDelegate(host: "192.0.2.1", pinStore: items.store, confirmCertificate: { _ in
            #expect(mode == "save-failed", "Do not offer to override an existing or unreadable pin")
            return true
        })
        #expect(try await decision(delegate, host: "192.0.2.1") == .cancelAuthenticationChallenge)
        #expect(await delegate.approvePendingCertificate() == false)
        #expect(items.state.withLock { $0.pin } == original)
        #expect(delegate.failure == (mode == "changed" ? .changedKey : .pinStorageFailed))
    }

    @Test(arguments: ["valid", "expired", "replacement"])
    func taskDelegatePreservesCertificatePolicy(certificate: String) async throws {
        let items = Items()
        let delegate = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(delegate, viaTask: true) == .useCredential)
        let outcome = try await decision(delegate, certificate: certificate, viaTask: true)
        #expect(outcome == (certificate == "valid" ? .useCredential : .cancelAuthenticationChallenge))
        #expect(delegate.certChanged == (certificate == "replacement"))
    }

    private final class Items: Sendable {
        struct State {
            var pin: Data?
            var readError: OSStatus?
            var addError: OSStatus?
            var deleteError: OSStatus?
        }
        let state = OSAllocatedUnfairLock(initialState: State())
        var store: CertificatePinStore {
            CertificatePinStore(read: { [self] _ in
                state.withLock { ($0.readError ?? ($0.pin == nil ? errSecItemNotFound : errSecSuccess), $0.pin) }
            }, add: { [self] query in
                let pin = query[kSecValueData as String] as? Data
                return state.withLock {
                    if let error = $0.addError { return error }
                    if $0.pin != nil { return errSecDuplicateItem }
                    $0.pin = pin
                    return errSecSuccess
                }
            }, delete: { [self] _ in
                state.withLock {
                    if let error = $0.deleteError { return error }
                    $0.pin = nil
                    return errSecSuccess
                }
            })
        }
    }

    @Test func transientRejectionRecoversWhenStoredPinMatches() async throws {
        let items = Items()
        let delegate = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(delegate) == .useCredential)
        // A transient cause such as a wrong system clock rejects the session.
        #expect(try await decision(delegate, certificate: "expired") == .cancelAuthenticationChallenge)
        #expect(delegate.failure == .invalidCertificate)
        // The stored pin proves this exact key was trusted; recovery is silent.
        #expect(try await decision(delegate) == .useCredential)
        #expect(delegate.failure == nil)
    }

    @Test func storageFailureAtInitRecoversOnlyAfterAPinExists() async throws {
        let items = Items()
        items.state.withLock { $0.readError = errSecInteractionNotAllowed }
        let delegate = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        items.state.withLock { $0.readError = nil }
        // Keychain healed but no pin exists: still no silent trust.
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        // Another delegate (or process) pins the controller; the wedged one recovers.
        #expect(try await decision(PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)) == .useCredential)
        #expect(try await decision(delegate) == .useCredential)
    }

    @Test func declinedFirstUseApprovalStaysDeclined() async throws {
        let items = Items()
        let delegate = PinnedCertDelegate(host: "192.0.2.1", pinStore: items.store, confirmCertificate: { _ in false })
        #expect(try await decision(delegate, host: "192.0.2.1", viaTask: true) == .cancelAuthenticationChallenge)
        #expect(await delegate.approvePendingCertificate() == false)
        #expect(delegate.failure == .nameMismatch)
        // Declining before any pin exists must not recover or re-prompt per poll.
        #expect(try await decision(delegate, host: "192.0.2.1", viaTask: true) == .cancelAuthenticationChallenge)
        #expect(items.state.withLock { $0.pin } == nil)
    }

    @Test func unreadablePinMustNotBecomeFirstUse() async throws {
        let items = Items()
        items.state.withLock { $0.readError = errSecInteractionNotAllowed }
        let delegate = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        #expect(items.state.withLock { $0.pin } == nil)
    }

    @Test func invalidatedDelegateCannotRepinAfterReset() async throws {
        let items = Items()
        let delegate = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        delegate.invalidate()
        try items.store.removeAll()
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        #expect(items.state.withLock { $0.pin } == nil)
    }

    @Test func removeAllPinsPropagatesFailureAndScopesTheQuery() throws {
        let queries = OSAllocatedUnfairLock(initialState: false)
        let store = CertificatePinStore(read: { _ in (errSecItemNotFound, nil) }, add: { _ in errSecSuccess }, delete: { query in
            let scoped = query[kSecAttrService as String] as? String == "com.unifbar.cert-pins"
                && query[kSecAttrAccount as String] == nil
                && query[kSecClass as String] as? String == kSecClassGenericPassword as String
            queries.withLock { $0 = scoped }
            return errSecAuthFailed
        })
        #expect(throws: CertificatePinStore.Failure.self) { try store.removeAll() }
        #expect(queries.withLock { $0 })
    }

    @Test func failedPersistenceMustNotGrantTrust() async throws {
        let items = Items()
        items.state.withLock { $0.addError = errSecAuthFailed }
        let delegate = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        items.state.withLock { $0.addError = nil }
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        #expect(try await decision(PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)) == .useCredential)
    }

    @Test func pinSurvivesRecreationAndRejectsChangedKey() async throws {
        let items = Items()
        #expect(try await decision(PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)) == .useCredential)
        let restarted = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(restarted) == .useCredential)
        #expect(try await decision(restarted, certificate: "replacement") == .cancelAuthenticationChallenge)
        #expect(restarted.certChanged)
        #expect(try await decision(restarted) == .cancelAuthenticationChallenge)
    }

    @Test func independentFirstUseDelegatesCannotReplaceOneAnothersPins() async throws {
        let items = Items()
        let first = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        let second = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(first) == .useCredential)
        #expect(try await decision(second, certificate: "replacement") == .cancelAuthenticationChallenge)
        #expect(try await decision(PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)) == .useCredential)
    }

    @Test func failedResetPreservesTrustAndSuccessfulResetRequiresNewDelegate() async throws {
        let items = Items()
        let delegate = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(delegate) == .useCredential)
        items.state.withLock { $0.deleteError = errSecAuthFailed }
        #expect(throws: CertificatePinStore.Failure.self) { try delegate.resetPin() }
        #expect(try await decision(delegate) == .useCredential)
        items.state.withLock { $0.deleteError = nil }
        try delegate.resetPin()
        #expect(try await decision(delegate) == .cancelAuthenticationChallenge)
        let replacement = PinnedCertDelegate(host: "fixture.invalid", pinStore: items.store)
        #expect(try await decision(replacement, certificate: "replacement") == .useCredential)
    }

    @Test func pinStorePreservesExistingValueAndReportsFailures() throws {
        let items = Items()
        let first = Data(repeating: 1, count: 32)
        let other = Data(repeating: 2, count: 32)
        try items.store.saveIfAbsent(first, host: "fixture.invalid")
        try items.store.saveIfAbsent(first, host: "fixture.invalid")
        #expect(throws: CertificatePinStore.Failure.self) { try items.store.saveIfAbsent(other, host: "fixture.invalid") }
        #expect(try items.store.load(host: "fixture.invalid") == first)
        items.state.withLock { $0.deleteError = errSecAuthFailed }
        #expect(throws: CertificatePinStore.Failure.self) { try items.store.remove(host: "fixture.invalid") }
        #expect(try items.store.load(host: "fixture.invalid") == first)
        items.state.withLock { $0.deleteError = nil }
        try items.store.remove(host: "fixture.invalid")
        #expect(try items.store.load(host: "fixture.invalid") == nil)
        items.state.withLock { $0.pin = Data() }
        #expect(throws: CertificatePinStore.Failure.self) { try items.store.load(host: "fixture.invalid") }
    }

    @Test(arguments: [("valid", "fixture.invalid", true), ("valid", "wrong.invalid", false),
                      ("expired", "fixture.invalid", false), ("future", "fixture.invalid", false),
                      ("expired", "wrong.invalid", false), ("future", "wrong.invalid", false)])
    func offlineCertificatePolicy(certificate: String, host: String, accepted: Bool) async throws {
        let delegate = PinnedCertDelegate(host: host, pinStore: Items().store)
        #expect(try await decision(delegate, certificate: certificate, host: host) ==
                (accepted ? .useCredential : .cancelAuthenticationChallenge))
    }

    @Test func unsetVerificationDateMeansNowNotTheReferenceEpoch() throws {
        let encoded = try #require(Self.certificates["valid"])
        let data = try #require(Data(base64Encoded: encoded))
        let cert = try #require(SecCertificateCreateWithData(nil, data as CFData))
        var optionalTrust: SecTrust?
        #expect(SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &optionalTrust) == errSecSuccess)
        let trust = try #require(optionalTrust)
        #expect(SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess)
        let before = Date()
        let actual = PinnedCertDelegate.verificationDate(for: SecTrustGetVerifyTime(trust))
        #expect(before <= actual && actual <= Date())
        // SecTrust.h documents zero for an unset time, even when this OS returns the current time.
        let zero = PinnedCertDelegate.verificationDate(for: 0)
        #expect(before <= zero && zero <= Date())
        let explicit = Date(timeIntervalSince1970: 1_788_825_600)
        #expect(SecTrustSetVerifyDate(trust, explicit as CFDate) == errSecSuccess)
        #expect(PinnedCertDelegate.verificationDate(for: SecTrustGetVerifyTime(trust)) == explicit)
    }

    private final class TrustSpace: URLProtectionSpace, @unchecked Sendable {
        let trust: SecTrust
        init(trust: SecTrust, host: String) {
            self.trust = trust
            super.init(host: host, port: 443, protocol: "https", realm: nil,
                       authenticationMethod: NSURLAuthenticationMethodServerTrust)
        }
        required init?(coder: NSCoder) { nil }
        override var serverTrust: SecTrust? { trust }
    }

    private final class Sender: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
    }

    private func decision(_ delegate: PinnedCertDelegate, certificate: String = "valid",
                          host: String = "fixture.invalid", viaTask: Bool = false) async throws -> URLSession.AuthChallengeDisposition {
        let encoded = try #require(Self.certificates[certificate])
        let data = try #require(Data(base64Encoded: encoded))
        let cert = try #require(SecCertificateCreateWithData(nil, data as CFData))
        var optionalTrust: SecTrust?
        #expect(SecTrustCreateWithCertificates(cert, SecPolicyCreateSSL(true, host as CFString), &optionalTrust) == errSecSuccess)
        let trust = try #require(optionalTrust)
        #expect(SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess)
        #expect(SecTrustSetAnchorCertificates(trust, [] as CFArray) == errSecSuccess)
        #expect(SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess)
        #expect(SecTrustSetVerifyDate(trust, Date(timeIntervalSince1970: 1_788_825_600) as CFDate) == errSecSuccess)
        let challenge = URLAuthenticationChallenge(protectionSpace: TrustSpace(trust: trust, host: host),
            proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: Sender())
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        if viaTask {
            let task = session.dataTask(with: URL(string: "https://fixture.invalid")!) // Never resumed.
            return await SameOriginRedirectDelegate(certificateDelegate: delegate)
                .urlSession(session, task: task, didReceive: challenge).0
        }
        return await delegate.urlSession(session, didReceive: challenge).0
    }

    // Offline EC P-256 self-signed fixtures, SAN fixture.invalid, serverAuth, no AIA/CRL.
    // OpenSSL 3.6 req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc
    // -subj /CN=fixture.invalid -addext subjectAltName=DNS:fixture.invalid
    // -addext basicConstraints=critical,CA:FALSE -addext keyUsage=critical,digitalSignature
    // -addext extendedKeyUsage=serverAuth -not_before <start> -not_after <end> -outform DER
    // valid/replacement: 2026..2027; expired: 2000..2001; future: 2090..2099.
    // Only public certificates are retained; synthetic private keys are not test resources.
    private static let certificates = [
        "valid": "MIIByTCCAW+gAwIBAgIUZgBO03tJPTvyMjs4J2hy2+aovqAwCgYIKoZIzj0EAwIwGjEYMBYGA1UEAwwPZml4dHVyZS5pbnZhbGlkMB4XDTI2MDEwMTAwMDAwMFoXDTI3MDEwMTAwMDAwMFowGjEYMBYGA1UEAwwPZml4dHVyZS5pbnZhbGlkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEBoz+usFG5kBjzVA32+ubLRetDNVPFFp3mlMCNgIzVt1oUtPp58vn1UIuAcI5tr+MWf2fZvkYQ3mqSWr7i2m9x6OBkjCBjzAdBgNVHQ4EFgQUFo8Xf6YP6DbcM5cUqGHs9W4/lB0wHwYDVR0jBBgwFoAUFo8Xf6YP6DbcM5cUqGHs9W4/lB0wGgYDVR0RBBMwEYIPZml4dHVyZS5pbnZhbGlkMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMAoGCCqGSM49BAMCA0gAMEUCIQCgi6X42Y3cfE7fqR0Mi7rdNMKjw1Lrm9iwvchabWCtegIgBLumjmy5aZ8QM6z96djlVsMoU9YFV1Ls74IJo3MzQlQ=",
        "replacement": "MIIByDCCAW+gAwIBAgIUPfAmsUD3VpHfeb40J/vSnxIeXfowCgYIKoZIzj0EAwIwGjEYMBYGA1UEAwwPZml4dHVyZS5pbnZhbGlkMB4XDTI2MDEwMTAwMDAwMFoXDTI3MDEwMTAwMDAwMFowGjEYMBYGA1UEAwwPZml4dHVyZS5pbnZhbGlkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEc2rkclfScdExFRa6ZkZcI2IfT1DVAA4OiZJT8tYRESsb1xOUV4tqEbG85ak0YnCSjzuww1kWk6OK3Zy7QTjFa6OBkjCBjzAdBgNVHQ4EFgQUlWTHFK/QmBHrSuiZaseCGGlMcOQwHwYDVR0jBBgwFoAUlWTHFK/QmBHrSuiZaseCGGlMcOQwGgYDVR0RBBMwEYIPZml4dHVyZS5pbnZhbGlkMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMAoGCCqGSM49BAMCA0cAMEQCIH3vPMGne9Fb1k4N+6sSIA/uhzCJKKWwcnMaPzgiItsxAiADUsx+lr0luMHO571iX9PIIdnwP18TAA6ovbJyS4gOqQ==",
        "expired": "MIIByDCCAW+gAwIBAgIUR3T3Zb2tD7WxtDrgnTRvJDUiwYEwCgYIKoZIzj0EAwIwGjEYMBYGA1UEAwwPZml4dHVyZS5pbnZhbGlkMB4XDTAwMDEwMTAwMDAwMFoXDTAxMDEwMTAwMDAwMFowGjEYMBYGA1UEAwwPZml4dHVyZS5pbnZhbGlkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFYl42MmjcoNCHEs3zthDbaNyx3WaBW/y762QC6uuPs/K/lxlmpRNh5iTYB3JfjMYX+TAKFEx9f1wfjvf0ZP82qOBkjCBjzAdBgNVHQ4EFgQUvzedGD8CZdeSvFyw8+xMBXZb3WMwHwYDVR0jBBgwFoAUvzedGD8CZdeSvFyw8+xMBXZb3WMwGgYDVR0RBBMwEYIPZml4dHVyZS5pbnZhbGlkMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMBMAoGCCqGSM49BAMCA0cAMEQCIDQ7BrKebQUJDTk+PkFgB1gc4OXo6N2wojWFg6JuAlJ+AiA/0jKJLCjwvbICzUqpgTs9qOnf8k4k/G4KFCceS2YB1A==",
        "future": "MIIBzTCCAXOgAwIBAgIUA9KWZGcY9w3LrJH+Otxvd0VfGBQwCgYIKoZIzj0EAwIwGjEYMBYGA1UEAwwPZml4dHVyZS5pbnZhbGlkMCIYDzIwOTAwMTAxMDAwMDAwWhgPMjA5OTAxMDEwMDAwMDBaMBoxGDAWBgNVBAMMD2ZpeHR1cmUuaW52YWxpZDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABBeNOHeYwis8Ik+NkjRGGI2TSpulI0D0hdyadJzxe4nCwwtlzwYvDLiQEMTnyur4PB8O5SyHoohvm06H0QFYcB2jgZIwgY8wHQYDVR0OBBYEFIWq+NBU0DaZ82IIKYLsFKcJzEDbMB8GA1UdIwQYMBaAFIWq+NBU0DaZ82IIKYLsFKcJzEDbMBoGA1UdEQQTMBGCD2ZpeHR1cmUuaW52YWxpZDAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDATAKBggqhkjOPQQDAgNIADBFAiEAs/YpBiID1RiNXdY415nqy7aalfWel9VTU7989/NSj/wCIFiJ1fOLjIAPg/emgoqOVsp/6QGaL805N94T/oR10tF3"
    ]
}
