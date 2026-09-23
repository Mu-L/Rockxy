import CryptoKit
import Foundation

// MARK: - RockxyNearbyTransferProtocol

enum RockxyNearbyTransferProtocol {
    static let version = 1
    static let serviceType = "_rockxy-xfer._tcp"
    static let maximumFrameSize = 12 * 1_024 * 1_024
    static let maximumTransactionCount = 10_000
    static let keyContext = Data("rockxy-nearby-transfer-v1".utf8)

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()
}

// MARK: - RockxyNearbyTransferMessageType

enum RockxyNearbyTransferMessageType: String, Codable {
    case hello
    case helloAcknowledgement
    case ready
    case payload
    case acknowledgement
    case decline
    case error
}

// MARK: - RockxyNearbyTransferMessage

struct RockxyNearbyTransferMessage: Codable {
    var type: RockxyNearbyTransferMessageType
    var protocolVersion: Int
    var transferID: String
    var deviceName: String?
    var sessionTitle: String?
    var transactionCount: Int?
    var publicKey: Data?
    var sealedPayload: Data?
    var message: String?
}

// MARK: - RockxyNearbyTransferError

enum RockxyNearbyTransferError: LocalizedError {
    case invalidFrame
    case frameTooLarge
    case invalidMessage
    case unsupportedVersion
    case invalidPeerKey
    case invalidEncryptedPayload
    case transferTooLarge
    case emptyTransfer
    case invalidTransaction
    case projectCatalogUnavailable

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidFrame:
            String(localized: "The nearby transfer frame is invalid.", bundle: RockxyLocalization.bundle)
        case .frameTooLarge:
            String(localized: "The nearby transfer exceeds Rockxy's local transfer size limit.", bundle: RockxyLocalization.bundle)
        case .invalidMessage:
            String(localized: "The nearby transfer message is incomplete.", bundle: RockxyLocalization.bundle)
        case .unsupportedVersion:
            String(localized: "The nearby Rockxy app uses an unsupported transfer protocol.", bundle: RockxyLocalization.bundle)
        case .invalidPeerKey:
            String(localized: "Rockxy could not verify the nearby device key.", bundle: RockxyLocalization.bundle)
        case .invalidEncryptedPayload:
            String(localized: "Rockxy could not decrypt the nearby transfer.", bundle: RockxyLocalization.bundle)
        case .transferTooLarge:
            String(localized: "The session is too large for nearby transfer.", bundle: RockxyLocalization.bundle)
        case .emptyTransfer:
            String(localized: "The transferred session contains no requests.", bundle: RockxyLocalization.bundle)
        case .invalidTransaction:
            String(localized: "The transferred session contains an invalid request.", bundle: RockxyLocalization.bundle)
        case .projectCatalogUnavailable:
            String(localized: "Projects could not be loaded, so Rockxy did not import the transferred session.", bundle: RockxyLocalization.bundle)
        }
    }
}

// MARK: - RockxyNearbyFrameAccumulator

struct RockxyNearbyFrameAccumulator {
    // MARK: Internal

    static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else {
            throw RockxyNearbyTransferError.invalidFrame
        }
        guard payload.count <= RockxyNearbyTransferProtocol.maximumFrameSize else {
            throw RockxyNearbyTransferError.frameTooLarge
        }

        let length = UInt32(payload.count)
        var framed = Data([
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ])
        framed.append(payload)
        return framed
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []

        while buffer.count >= MemoryLayout<UInt32>.size {
            let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0 else {
                throw RockxyNearbyTransferError.invalidFrame
            }
            guard length <= RockxyNearbyTransferProtocol.maximumFrameSize else {
                throw RockxyNearbyTransferError.frameTooLarge
            }

            let frameLength = Int(length)
            guard buffer.count >= 4 + frameLength else {
                break
            }

            frames.append(buffer.subdata(in: 4 ..< 4 + frameLength))
            buffer.removeSubrange(0 ..< 4 + frameLength)
        }

        return frames
    }

    // MARK: Private

    private var buffer = Data()
}

// MARK: - RockxyNearbyPairingCrypto

enum RockxyNearbyPairingCrypto {
    struct SessionKeys {
        let encryptionKey: SymmetricKey
        let verificationCode: String
    }

    static func deriveKeys(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKeyData: Data,
        transferID: String
    )
        throws -> SessionKeys
    {
        let peerKey: P256.KeyAgreement.PublicKey
        do {
            peerKey = try P256.KeyAgreement.PublicKey(x963Representation: peerPublicKeyData)
        } catch {
            throw RockxyNearbyTransferError.invalidPeerKey
        }

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerKey)
        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(transferID.utf8),
            sharedInfo: RockxyNearbyTransferProtocol.keyContext,
            outputByteCount: 32
        )
        let authentication = HMAC<SHA256>.authenticationCode(
            for: Data("rockxy-pairing-code".utf8),
            using: key
        )
        let codeValue = authentication.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        return SessionKeys(
            encryptionKey: key,
            verificationCode: String(format: "%06u", codeValue)
        )
    }

    static func seal(_ data: Data, using key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw RockxyNearbyTransferError.invalidEncryptedPayload
        }
        return combined
    }

    static func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        } catch {
            throw RockxyNearbyTransferError.invalidEncryptedPayload
        }
    }
}
