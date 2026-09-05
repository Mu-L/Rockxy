import Foundation
@testable import Rockxy

// MARK: - CertificateFixtureCleanup

/// Teardown for one `installSharedTestOverrides` fixture.
///
/// Idempotent and callable from any thread or executor: only the first call does work, so a
/// cleanup that has already run — or one whose test finished long ago — can never clear a later
/// fixture's overrides, delete its key or directory, or end its turn on the gate.
private final class CertificateFixtureCleanup: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        lease: CertificateFixtureGate.Lease,
        keyLabel: String,
        certificateLabel: String,
        storageDirectory: URL
    ) {
        self.lease = lease
        self.keyLabel = keyLabel
        self.certificateLabel = certificateLabel
        self.storageDirectory = storageDirectory
    }

    // MARK: Internal

    func run() {
        lock.lock()
        if hasRun {
            lock.unlock()
            return
        }
        hasRun = true
        lock.unlock()

        // Remove the certificate before dropping the overrides: the active certificate label
        // is derived from the key-label override.
        try? KeychainHelper.removeCertificate(label: certificateLabel)
        CertificateStore.keychainKeyLabelOverride = nil
        CertificateStore.storageDirectoryOverride = nil
        try? KeychainHelper.deletePrivateKey(label: keyLabel)
        try? FileManager.default.removeItem(at: storageDirectory)

        // Released last: restoration is complete before the next waiter can observe the store.
        certificateFixtureGate.release(lease)
    }

    // MARK: Private

    private let lease: CertificateFixtureGate.Lease
    private let keyLabel: String
    private let certificateLabel: String
    private let storageDirectory: URL
    private let lock = NSLock()
    private var hasRun = false
}

// MARK: - Fixtures

/// Sets CertificateStore overrides for test isolation: test-specific Keychain label
/// and a unique temp directory for filesystem operations. Waits on the shared
/// `certificateFixtureGate` so no two suites hold override state at the same time.
///
/// The override moves the root CA *certificate* label with the key label, so anything
/// reached through `CertificateManager` — install, trust metadata checks, trust removal,
/// reset — addresses the test namespace and never the production root CA.
/// Returns a cleanup closure that MUST be called (typically via `defer`).
func installSharedTestOverrides() async throws -> (
    label: String,
    certificateLabel: String,
    storageDir: URL,
    cleanup: @Sendable () -> Void
) {
    let lease = try await certificateFixtureGate.acquire()

    // Granted, but this caller is already going away: hand the turn back before any override is
    // mutated, so a cancelled test never leaves fixture state installed.
    if Task.isCancelled {
        certificateFixtureGate.release(lease)
        throw CancellationError()
    }

    let testLabel = TestIdentity.keychainProbeLabel + ".\(UUID().uuidString)"
    let testDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("RockxyTests-\(UUID().uuidString)", isDirectory: true)

    CertificateStore.keychainKeyLabelOverride = testLabel
    CertificateStore.storageDirectoryOverride = testDir
    let testCertificateLabel = CertificateStore.activeKeychainCertificateLabel

    let teardown = CertificateFixtureCleanup(
        lease: lease,
        keyLabel: testLabel,
        certificateLabel: testCertificateLabel,
        storageDirectory: testDir
    )

    return (testLabel, testCertificateLabel, testDir, { teardown.run() })
}

/// Runs `body` while owning the shared certificate fixture gate with no `CertificateStore`
/// overrides installed, so the *default* per-process test namespace is the one under test. Any
/// override belonging to the caller is restored afterwards.
///
/// Only the default test namespace is ever touched: `RockxyIdentity.isRunningTests` keeps those
/// labels distinct from the production root CA labels.
func withDefaultCertificateNamespace<T>(_ body: () throws -> T) async throws -> T {
    let lease = try await certificateFixtureGate.acquire()

    if Task.isCancelled {
        certificateFixtureGate.release(lease)
        throw CancellationError()
    }

    let previousLabel = CertificateStore.keychainKeyLabelOverride
    let previousDirectory = CertificateStore.storageDirectoryOverride
    CertificateStore.keychainKeyLabelOverride = nil
    CertificateStore.storageDirectoryOverride = nil

    defer {
        CertificateStore.keychainKeyLabelOverride = previousLabel
        CertificateStore.storageDirectoryOverride = previousDirectory
        certificateFixtureGate.release(lease)
    }

    return try body()
}
