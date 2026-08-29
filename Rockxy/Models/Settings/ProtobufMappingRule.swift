import Foundation

// MARK: - ProtobufPayloadEncoding

enum ProtobufPayloadEncoding: String, Codable, CaseIterable, Identifiable {
    case auto
    case singleMessage
    case delimitedList

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .auto:
            String(localized: "Auto", bundle: RockxyLocalization.bundle)
        case .singleMessage:
            String(localized: "Single Message", bundle: RockxyLocalization.bundle)
        case .delimitedList:
            String(localized: "Delimited List", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ProtobufMappingRule

struct ProtobufMappingRule: Codable, Equatable, Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        urlPattern: String,
        method: HTTPMethodFilter = .any,
        matchType: RuleMatchType = .wildcard,
        includeSubpaths: Bool = true,
        schemaID: UUID? = nil,
        messageType: String = "",
        requestMessageType: String? = nil,
        responseMessageType: String? = nil,
        payloadEncoding: ProtobufPayloadEncoding = .auto
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.urlPattern = urlPattern
        self.method = method
        self.matchType = matchType
        self.includeSubpaths = includeSubpaths
        self.schemaID = schemaID
        self.messageType = messageType
        self.requestMessageType = requestMessageType
        self.responseMessageType = responseMessageType
        self.payloadEncoding = payloadEncoding
    }

    // MARK: Internal

    let id: UUID
    var isEnabled: Bool
    var urlPattern: String
    var method: HTTPMethodFilter
    var matchType: RuleMatchType
    var includeSubpaths: Bool
    var schemaID: UUID?
    var messageType: String
    var requestMessageType: String?
    var responseMessageType: String?
    var payloadEncoding: ProtobufPayloadEncoding

    /// Returns a copy with editable fields replaced while preserving identity and saved state.
    ///
    /// `id` and `isEnabled` are intentionally carried over so editing a disabled definition
    /// never silently re-enables it.
    func withEditedFields(
        urlPattern: String,
        method: HTTPMethodFilter,
        matchType: RuleMatchType,
        includeSubpaths: Bool,
        schemaID: UUID?,
        messageType: String,
        requestMessageType: String?,
        responseMessageType: String?,
        payloadEncoding: ProtobufPayloadEncoding
    )
        -> ProtobufMappingRule
    {
        ProtobufMappingRule(
            id: id,
            isEnabled: isEnabled,
            urlPattern: urlPattern,
            method: method,
            matchType: matchType,
            includeSubpaths: includeSubpaths,
            schemaID: schemaID,
            messageType: messageType,
            requestMessageType: requestMessageType,
            responseMessageType: responseMessageType,
            payloadEncoding: payloadEncoding
        )
    }
}

// MARK: - ProtobufSchemaReference

/// How a mapping definition's stored schema id resolves against the local schema list.
enum ProtobufSchemaReference: Equatable {
    /// No schema id is stored on the definition.
    case notSelected
    /// The stored id resolves to a local schema with this file name.
    case selected(String)
    /// A non-nil schema id is stored but no matching local schema exists.
    case missing

    // MARK: Internal

    var displayLabel: String {
        switch self {
        case .notSelected:
            String(localized: "Not selected", bundle: RockxyLocalization.bundle)
        case let .selected(name):
            name
        case .missing:
            String(localized: "Missing Schema", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - ProtobufMappingRuleValidationError

enum ProtobufMappingRuleValidationError: LocalizedError, Equatable {
    case emptyPattern
    case invalidMessageType

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emptyPattern:
            String(localized: "Matching rule cannot be empty.", bundle: RockxyLocalization.bundle)
        case .invalidMessageType:
            String(
                localized: "Message type can only contain letters, numbers, underscores, periods, and dollar signs.",
                bundle: RockxyLocalization.bundle
            )
        }
    }
}
