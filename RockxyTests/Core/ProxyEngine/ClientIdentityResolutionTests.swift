import Foundation
@testable import Rockxy
import Testing

// MARK: - IntBox

private final class IntBox: @unchecked Sendable {
    // MARK: Internal

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    // MARK: Private

    private let lock = NSLock()
    private var value = 0
}

// MARK: - ClientIdentityResolutionTests

struct ClientIdentityResolutionTests {
    // MARK: Internal

    // MARK: - Directional endpoint matching

    @Test("matches a local client to its owning pid via exact source endpoint")
    func matchesLocalClient() {
        let records = [
            ProxyConnectionRecord(
                pid: 4_242, command: "curl",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
            // Proxy's own reverse-accepted socket (source is the proxy port) — must be ignored.
            ProxyConnectionRecord(
                pid: 999, command: "Rockxy",
                sourceHost: "127.0.0.1", sourcePort: 9_090,
                destHost: "127.0.0.1", destPort: 54_321
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        let pid = ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999)
        #expect(pid == 4_242)
    }

    @Test("remote client source is never matched to an application")
    func remoteClientNotMatched() {
        let records = [
            ProxyConnectionRecord(
                pid: 4_242, command: "curl",
                sourceHost: "192.168.1.50", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "192.168.1.50", clientPort: 54_321, proxyPort: 9_090)
        #expect(ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999) == nil)
    }

    @Test("proxy's own pid is excluded from matching")
    func excludesOwnPID() {
        let records = [
            ProxyConnectionRecord(
                pid: 999, command: "Rockxy",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        #expect(ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999) == nil)
    }

    @Test("ambiguous source-port matches decline rather than guess")
    func ambiguousDeclines() {
        let records = [
            ProxyConnectionRecord(
                pid: 1, command: "a",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
            ProxyConnectionRecord(
                pid: 2, command: "b",
                sourceHost: "127.0.0.1", sourcePort: 54_321,
                destHost: "127.0.0.1", destPort: 9_090
            ),
        ]
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        #expect(ClientConnectionMatcher.matchingPID(records: records, descriptor: descriptor, excludePID: 999) == nil)
    }

    // MARK: - Snapshot freshness / coalescing

    @Test("a snapshot started after accept is reused for a later lookup with the same accept time")
    func freshSnapshotReused() async {
        let collections = IntBox()
        let nowBox = IntBox()
        let times: [UInt64] = [2_000, 4_000]
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                _ = collections.next()
                return [Self.matchingRecord]
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            now: { DispatchTime(uptimeNanoseconds: times[min(nowBox.next(), times.count - 1)]) },
            excludePID: 999
        )

        let descriptor = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        _ = await resolver.resolveIdentity(descriptor: descriptor)
        _ = await resolver.resolveIdentity(descriptor: descriptor)

        #expect(collections.count() == 1)
    }

    @Test("a stale snapshot forces a fresh collection")
    func staleSnapshotRecollected() async {
        let collections = IntBox()
        let nowBox = IntBox()
        let times: [UInt64] = [2_000, 4_000]
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                _ = collections.next()
                return [Self.matchingRecord]
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            now: { DispatchTime(uptimeNanoseconds: times[min(nowBox.next(), times.count - 1)]) },
            excludePID: 999
        )

        let first = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        _ = await resolver.resolveIdentity(descriptor: first)

        // Accepted after the first collection started (2_000) ⇒ not fresh ⇒ recollect.
        let second = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 3_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        _ = await resolver.resolveIdentity(descriptor: second)

        #expect(collections.count() == 2)
    }

    @Test("concurrent accepts coalesce into one bounded connection-table collection")
    func concurrentAcceptsCoalesce() async {
        let collections = IntBox()
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in
                _ = collections.next()
                return [Self.matchingRecord]
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            now: { DispatchTime(uptimeNanoseconds: 10_000) },
            coalescingDelay: .milliseconds(20),
            excludePID: 999
        )
        let first = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 1_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )
        let second = makeDescriptor(
            acceptedAt: DispatchTime(uptimeNanoseconds: 2_000),
            clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090
        )

        async let firstIdentity = resolver.resolveIdentity(descriptor: first)
        async let secondIdentity = resolver.resolveIdentity(descriptor: second)
        let identities = await [firstIdentity, secondIdentity]

        #expect(identities.allSatisfy { $0 == Self.sampleIdentity })
        #expect(collections.count() == 1)
    }

    // MARK: - Resolution outcomes

    @Test("resolver returns the provided identity for a matched connection")
    func resolvesIdentity() async {
        let resolver = makeResolver(records: [Self.matchingRecord])
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        let identity = await resolver.resolveIdentity(descriptor: descriptor)
        #expect(identity == Self.sampleIdentity)
    }

    @Test("remote descriptor short-circuits without collecting the table")
    func remoteShortCircuits() async {
        let collections = IntBox()
        let resolver = ClientIdentityResolver(
            connectionTableProvider: { _, _ in _ = collections.next()
                return []
            },
            identityProvider: { _, _ in Self.sampleIdentity },
            excludePID: 999
        )
        let descriptor = makeDescriptor(clientHost: "10.0.0.9", clientPort: 54_321, proxyPort: 9_090)
        let identity = await resolver.resolveIdentity(descriptor: descriptor)
        #expect(identity == nil)
        #expect(collections.count() == 0)
    }

    @Test("empty table (timeout / no match) resolves to nil")
    func timeoutResolvesNil() async {
        let resolver = makeResolver(records: [])
        let descriptor = makeDescriptor(clientHost: "127.0.0.1", clientPort: 54_321, proxyPort: 9_090)
        #expect(await resolver.resolveIdentity(descriptor: descriptor) == nil)
    }

    // MARK: - lsof parsing

    @Test("parseConnectionTable parses IPv4 and IPv6 directional records")
    func parsesConnectionTable() {
        let output = """
        p4242
        ccurl
        n127.0.0.1:54321->127.0.0.1:9090
        p777
        cChrome
        n[::1]:60000->[::1]:9090
        """
        let records = ProcessResolver.parseConnectionTable(output)
        #expect(records.count == 2)
        #expect(records[0].pid == 4_242)
        #expect(records[0].sourcePort == 54_321)
        #expect(records[0].destPort == 9_090)
        #expect(records[1].pid == 777)
        #expect(records[1].sourceHost == "::1")
        #expect(records[1].sourcePort == 60_000)
        #expect(records[1].destPort == 9_090)
    }

    // MARK: - Transaction stamping

    @Test("stamping callback attaches identity and clientApp without overriding existing values")
    func stampingCallback() {
        let handle = ClientIdentityHandle(
            descriptor: makeDescriptor(clientHost: "127.0.0.1", clientPort: 1, proxyPort: 9_090),
            resolver: makeResolver(records: [])
        )
        // No stamping when identity is unresolved (handle currentIdentity is nil).
        let unstamped = makeTransaction()
        ProxyServer.makeIdentityStampingCallback(handle: handle, downstream: { _ in })(unstamped)
        #expect(unstamped.clientApplicationIdentity == nil)

        // A pre-set clientApp is preserved even if identity would supply one.
        let preset = makeTransaction()
        preset.clientApp = "Existing"
        ProxyServer.makeIdentityStampingCallback(handle: nil, downstream: { _ in })(preset)
        #expect(preset.clientApp == "Existing")
    }

    // MARK: Private

    private static let matchingRecord = ProxyConnectionRecord(
        pid: 4_242, command: "curl",
        sourceHost: "127.0.0.1", sourcePort: 54_321,
        destHost: "127.0.0.1", destPort: 9_090
    )

    private static let sampleIdentity = ClientApplicationIdentity.executable(
        normalizedPath: "/usr/bin/curl",
        displayName: "curl"
    )

    private func makeResolver(records: [ProxyConnectionRecord]) -> ClientIdentityResolver {
        ClientIdentityResolver(
            connectionTableProvider: { _, _ in records },
            identityProvider: { _, _ in Self.sampleIdentity },
            excludePID: 999
        )
    }

    private func makeDescriptor(
        acceptedAt: DispatchTime = DispatchTime(uptimeNanoseconds: 1_000),
        clientHost: String?,
        clientPort: UInt16?,
        proxyPort: Int
    )
        -> ProxyConnectionDescriptor
    {
        ProxyConnectionDescriptor(
            acceptedAt: acceptedAt,
            clientHost: clientHost,
            clientPort: clientPort,
            proxyHost: "127.0.0.1",
            proxyPort: proxyPort
        )
    }

    private func makeTransaction() -> HTTPTransaction {
        HTTPTransaction(
            request: HTTPRequestData(
                method: "GET",
                url: URL(string: "https://example.com/")!,
                httpVersion: "1.1",
                headers: [],
                body: nil,
                contentType: nil
            ),
            state: .completed
        )
    }
}
