import Foundation
import os
import Testing
@testable import UniFiBar

struct TrustPromptGateTests {
    private func details() -> PinnedCertDelegate.CertificateDetails {
        PinnedCertDelegate.CertificateDetails(host: "192.0.2.1", fingerprint: "AA:BB:CC")
    }

    @Test func disarmedGateNeverPrompts() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let gate = TrustPromptGate(prompt: { _ in
            calls.withLock { $0 += 1 }
            return true
        })

        #expect(await gate.consume(details()) == false)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func armedGatePromptsOnceAndReturnsTheUserChoice() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let gate = TrustPromptGate(prompt: { _ in
            calls.withLock { $0 += 1 }
            return true
        })

        gate.arm()
        #expect(await gate.consume(details()) == true)
        #expect(calls.withLock { $0 } == 1)

        // The permission is one-shot, so a later challenge fails closed.
        #expect(await gate.consume(details()) == false)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func declinedPromptIsNotRetriedWithoutANewArm() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let gate = TrustPromptGate(prompt: { _ in
            calls.withLock { $0 += 1 }
            return false
        })

        gate.arm()
        #expect(await gate.consume(details()) == false)
        #expect(await gate.consume(details()) == false)
        #expect(calls.withLock { $0 } == 1)
    }
}
