import CryptoKit
import Foundation
import Security

enum LocalFileIntegrityError: Error, LocalizedError, Sendable {
    case invalidEnvelope
    case integrityCheckFailed
    case keychainFailure(OSStatus)
    case randomGenerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            "The local data file is not in a supported format."
        case .integrityCheckFailed:
            "The local data file failed its integrity check and was not trusted."
        case let .keychainFailure(status):
            "The local integrity key could not be accessed (\(status))."
        case let .randomGenerationFailed(status):
            "A local integrity key could not be generated (\(status))."
        }
    }
}

struct LocalFileAuthenticator: Sendable {
    private static let service = "com.oliverames.SkylightBridge.local-integrity"

    private let account: String?
    private let testKey: Data?

    init(account: String) {
        self.account = account
        testKey = nil
    }

    init(testKey: Data) {
        account = nil
        self.testKey = testKey
    }

    func seal<Value: Encodable>(_ value: Value) throws -> Data {
        let payload = try Self.payloadEncoder.encode(value)
        let authenticationTag = Data(HMAC<SHA256>.authenticationCode(
            for: payload,
            using: SymmetricKey(data: try keyData())
        ))
        return try JSONEncoder().encode(SignedLocalFileEnvelope(
            version: 1,
            payload: payload,
            authenticationTag: authenticationTag
        ))
    }

    func open<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let envelope: SignedLocalFileEnvelope
        do {
            envelope = try JSONDecoder().decode(SignedLocalFileEnvelope.self, from: data)
        } catch {
            throw LocalFileIntegrityError.invalidEnvelope
        }
        guard envelope.version == 1 else {
            throw LocalFileIntegrityError.invalidEnvelope
        }

        let isAuthentic = HMAC<SHA256>.isValidAuthenticationCode(
            envelope.authenticationTag,
            authenticating: envelope.payload,
            using: SymmetricKey(data: try keyData())
        )
        guard isAuthentic else {
            throw LocalFileIntegrityError.integrityCheckFailed
        }
        return try Self.payloadDecoder.decode(type, from: envelope.payload)
    }

    private func keyData() throws -> Data {
        if let testKey {
            return testKey
        }
        guard let account else {
            throw LocalFileIntegrityError.invalidEnvelope
        }
        return try Self.loadOrCreateKey(account: account)
    }

    private static func loadOrCreateKey(account: String) throws -> Data {
        let query = keychainQuery(account: account)
        if let existing = try loadKey(query: query) {
            return existing
        }

        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw LocalFileIntegrityError.randomGenerationFailed(randomStatus)
        }

        var attributes = query
        attributes[kSecValueData] = key
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem, let existing = try loadKey(query: query) {
            return existing
        }
        guard addStatus == errSecSuccess else {
            throw LocalFileIntegrityError.keychainFailure(addStatus)
        }
        return key
    }

    private static func loadKey(query: [CFString: Any]) throws -> Data? {
        var readQuery = query
        readQuery[kSecReturnData] = true
        readQuery[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LocalFileIntegrityError.keychainFailure(status)
        }
        return data
    }

    private static func keychainQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    private static var payloadEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var payloadDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                guard seconds.isFinite else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Date timestamp must be finite."
                    )
                }
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let legacyFormatter = ISO8601DateFormatter()
            legacyFormatter.formatOptions = [.withInternetDateTime]
            if let date = legacyFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Date is not a supported timestamp or ISO 8601 value."
            )
        }
        return decoder
    }
}

private struct SignedLocalFileEnvelope: Codable {
    let version: Int
    let payload: Data
    let authenticationTag: Data
}
