import Foundation
import Security
import ErgoPluginKit

public final class SecretStore: SecretStoring {
    public struct KeychainError: Error { public let status: OSStatus }

    private let service: String

    public init(service: String = "com.jrainlau.ergo") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func secret(_ account: String) -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String?, account: String) throws {
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(baseQuery(account) as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound { throw KeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add[kSecValueData as String] = data
            let s = SecItemAdd(add as CFDictionary, nil)
            if s != errSecSuccess { throw KeychainError(status: s) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }
}
