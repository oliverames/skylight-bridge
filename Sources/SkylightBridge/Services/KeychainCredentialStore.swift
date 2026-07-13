import Foundation
import Security

enum KeychainCredentialStoreError: Error, LocalizedError, Sendable {
    case unexpectedData
    case invalidStringEncoding
    case operationFailed(status: OSStatus, message: String)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            "The Keychain returned a value in an unexpected format."
        case .invalidStringEncoding:
            "The credential could not be encoded as UTF-8."
        case let .operationFailed(status, message):
            "Keychain operation failed (\(status)): \(message)"
        }
    }
}

actor KeychainCredentialStore {
    private let service: String

    init(service: String = "com.oliverames.SkylightBridge.skylight") {
        self.service = service
    }

    func save(_ value: String, for account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainCredentialStoreError.invalidStringEncoding
        }
        try save(data, for: account)
    }

    func save(_ data: Data, for account: String) throws {
        let query = baseQuery(for: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw error(for: updateStatus)
        }

        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw error(for: addStatus)
        }
    }

    func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialStoreError.invalidStringEncoding
        }
        return value
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw error(for: status)
        }
        guard let data = result as? Data else {
            throw KeychainCredentialStoreError.unexpectedData
        }
        return data
    }

    func delete(for account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw error(for: status)
        }
    }

    private func baseQuery(for account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true
        ]
    }

    private func error(for status: OSStatus) -> KeychainCredentialStoreError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        return .operationFailed(status: status, message: message)
    }
}
