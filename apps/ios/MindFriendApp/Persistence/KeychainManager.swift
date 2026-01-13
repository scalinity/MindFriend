import Foundation
import Security

/// Manages secure token storage in Keychain - thread-safe via actor isolation
actor KeychainManager {
    private let service = "com.mindfriend.app"

    private enum Key: String {
        case accessToken
        case refreshToken
        case tokenExpiry
    }

    // MARK: - Token Storage

    func getAccessToken() -> String? {
        getString(for: .accessToken)
    }

    func setAccessToken(_ value: String?) {
        if let value = value {
            setString(value, for: .accessToken)
        } else {
            delete(key: .accessToken)
        }
    }

    func getRefreshToken() -> String? {
        getString(for: .refreshToken)
    }

    func setRefreshToken(_ value: String?) {
        if let value = value {
            setString(value, for: .refreshToken)
        } else {
            delete(key: .refreshToken)
        }
    }

    func getTokenExpiry() -> Date? {
        guard let timestamp = getString(for: .tokenExpiry),
              let interval = TimeInterval(timestamp) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    func setTokenExpiry(_ date: Date?) {
        if let date = date {
            setString(String(date.timeIntervalSince1970), for: .tokenExpiry)
        } else {
            delete(key: .tokenExpiry)
        }
    }

    // MARK: - Convenience Methods

    func saveTokens(_ tokens: AuthTokens) {
        setAccessToken(tokens.accessToken)
        setRefreshToken(tokens.refreshToken)
        setTokenExpiry(Date().addingTimeInterval(TimeInterval(tokens.expiresIn)))
    }

    func clearTokens() {
        setAccessToken(nil)
        setRefreshToken(nil)
        setTokenExpiry(nil)
    }

    func hasValidTokens() -> Bool {
        guard getAccessToken() != nil, getRefreshToken() != nil else {
            return false
        }
        return true
    }

    func isAccessTokenExpired() -> Bool {
        guard let expiry = getTokenExpiry() else { return true }
        // Consider expired if less than 60 seconds remaining
        return expiry.timeIntervalSinceNow < 60
    }

    // MARK: - Private Keychain Operations

    private func getString(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func setString(_ value: String, for key: Key) {
        guard let data = value.data(using: .utf8) else { return }

        // First try to update existing item
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, create it
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func delete(key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        SecItemDelete(query as CFDictionary)
    }
}
