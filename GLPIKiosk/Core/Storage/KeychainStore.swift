// GLPIKiosk — KeychainStore.swift
// Stockage sécurisé des secrets dans le Keychain iOS.

import Foundation
import Security

enum KeychainStore {
    private static let service = "fr.jcd.glpikiosk"
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    // MARK: - Write

    @discardableResult
    static func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]

        // Tente de mettre à jour si existe
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = accessibility
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    // MARK: - Read

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass              as String: kSecClassGenericPassword,
            kSecAttrService        as String: service,
            kSecAttrAccount        as String: key,
            kSecReturnData         as String: true,
            kSecMatchLimit         as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str  = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: - Delete

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Codable helpers

    static func setCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value),
           let str  = String(data: data, encoding: .utf8) {
            set(str, forKey: key)
        }
    }

    static func getCodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let str  = get(key),
              let data = str.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Keys

extension KeychainStore {
    static let keyAppToken      = "kiosk_app_token"
    static let keyClientSecret  = "kiosk_client_secret"
    static let keyUserToken     = "kiosk_user_token"
    static let keyOAuthTokens   = "kiosk_oauth_tokens"
    static let keyOAuthPassword = "kiosk_oauth_password"
    static let keyAdminCode     = "kiosk_admin_code"
}
