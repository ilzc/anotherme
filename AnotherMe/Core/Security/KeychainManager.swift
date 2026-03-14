import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
    case interactionNotAllowed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed: \(status)"
        case .readFailed(let status):
            return "Keychain read failed: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed: \(status)"
        case .dataConversionFailed:
            return "Keychain data conversion failed"
        case .interactionNotAllowed:
            return "Keychain is locked or interaction not allowed"
        }
    }
}

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    private let service = "com.anotherme"

    private init() {}

    // MARK: - Database Encryption Key

    private let dbKeyAccount = "database-encryption-key"

    func getOrCreateDatabaseKey() throws -> Data {
        if let existing = try? getData(account: dbKeyAccount) {
            return existing
        }
        let newKey = generateRandomKey(bytes: 32)
        try saveData(newKey, account: dbKeyAccount)
        return newKey
    }

    func deleteDatabaseKey() throws {
        try deleteData(account: dbKeyAccount)
    }

    // MARK: - AI API Key Storage

    func saveAPIKey(_ key: String, for slotName: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        let account = "ai.\(slotName).apikey"
        // Delete existing before saving (upsert)
        try? deleteData(account: account)
        try saveData(data, account: account)
    }

    func getAPIKey(for slotName: String) -> String? {
        let account = "ai.\(slotName).apikey"
        guard let data = try? getData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey(for slotName: String) throws {
        try deleteData(account: "ai.\(slotName).apikey")
    }

    // MARK: - Private Helpers

    private func generateRandomKey(bytes: Int) -> Data {
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes, buffer.baseAddress!)
        }
        return data
    }

    private func saveData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        case errSecDuplicateItem:
            // Item already exists — update it instead
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(updateStatus)
            }
        default:
            throw KeychainError.saveFailed(status)
        }
    }

    private func getData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        default:
            throw KeychainError.readFailed(status)
        }
    }


    private func deleteData(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
