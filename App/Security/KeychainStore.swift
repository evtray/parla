import Foundation
import Security

/// La API key vive solo aquí. Nunca en UserDefaults ni en disco en claro.
struct KeychainStore: Sendable {
    static let shared = KeychainStore()

    private let service = "app.schoolaid.Parla"
    private let account = "anthropic-api-key"

    var apiKey: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let key = String(data: data, encoding: .utf8),
                  !key.isEmpty
            else { return nil }
            return key
        }
        nonmutating set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var insert = base
            insert[kSecValueData as String] = Data(newValue.utf8)
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
