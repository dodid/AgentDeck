import Foundation
import Security

struct ConnectionCredentials: Codable, Equatable, Sendable {
    let accessKeyID: String
    let secretAccessKey: String
}

protocol ConnectionCredentialStore: Sendable {
    func load() throws -> ConnectionCredentials?
    func save(_ credentials: ConnectionCredentials) throws
}

struct KeychainConnectionCredentialStore: ConnectionCredentialStore {
    private let service: String
    private let account = "r2-relay-v3"

    init(service: String = Bundle.main.bundleIdentifier ?? "ClawChat") {
        self.service = service
    }

    func load() throws -> ConnectionCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainCredentialError(status: status)
        }
        return try JSONDecoder().decode(ConnectionCredentials.self, from: data)
    }

    func save(_ credentials: ConnectionCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialError(status: updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialError(status: addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct KeychainCredentialError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain operation failed (\(status))."
    }
}
