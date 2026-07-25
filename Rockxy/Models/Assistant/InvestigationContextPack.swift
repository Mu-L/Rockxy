import Foundation

// MARK: - InvestigationContextLimits

struct InvestigationContextLimits: Equatable {
    static let `default` = InvestigationContextLimits()

    var maxTransactions = 5
    var maxBodyBytes = 4 * 1_024
    var maxHeaders = 32
    var maxHeaderValueCharacters = 256
    var maxURLCharacters = 2_048
    var maxOutboundBytes = 160 * 1_024
}

// MARK: - InvestigationContextManifest

struct InvestigationContextManifest: Equatable {
    // MARK: Lifecycle

    init(
        requestCount: Int,
        outboundBytes: Int,
        redactedHeaderCount: Int,
        redactedQueryCount: Int,
        redactedURLCredentialCount: Int = 0,
        redactedBodyFieldCount: Int,
        truncatedBodyCount: Int,
        omittedBinaryBodyCount: Int,
        omittedTransactionCount: Int
    ) {
        self.requestCount = requestCount
        self.outboundBytes = outboundBytes
        self.redactedHeaderCount = redactedHeaderCount
        self.redactedQueryCount = redactedQueryCount
        self.redactedURLCredentialCount = redactedURLCredentialCount
        self.redactedBodyFieldCount = redactedBodyFieldCount
        self.truncatedBodyCount = truncatedBodyCount
        self.omittedBinaryBodyCount = omittedBinaryBodyCount
        self.omittedTransactionCount = omittedTransactionCount
    }

    // MARK: Internal

    let requestCount: Int
    let outboundBytes: Int
    let redactedHeaderCount: Int
    let redactedQueryCount: Int
    let redactedURLCredentialCount: Int
    let redactedBodyFieldCount: Int
    let truncatedBodyCount: Int
    let omittedBinaryBodyCount: Int
    let omittedTransactionCount: Int

    var redactedFieldCount: Int {
        redactedHeaderCount + redactedQueryCount + redactedURLCredentialCount + redactedBodyFieldCount
    }
}

// MARK: - InvestigationContextPack

struct InvestigationContextPack: Identifiable, Equatable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        scopeTransactionIDs: [UUID],
        payload: Data,
        preview: String,
        manifest: InvestigationContextManifest
    ) {
        self.id = id
        self.scopeTransactionIDs = scopeTransactionIDs
        self.payload = payload
        self.preview = preview
        self.manifest = manifest
    }

    // MARK: Internal

    let id: UUID
    let scopeTransactionIDs: [UUID]
    let payload: Data
    let preview: String
    let manifest: InvestigationContextManifest
}
