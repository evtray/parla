import Foundation
import Security

/// La API key vive solo aquí. Nunca en UserDefaults ni en disco en claro.
struct KeychainStore: Sendable {
    static let shared = KeychainStore()

    private let service = "app.schoolaid.Parla"
    private let account = "anthropic-api-key"

    var apiKey: String? {
        get {
            #if DEBUG
            // Afordancia de desarrollo: cada compilación firmada ad hoc es una app
            // nueva para el Llavero y este pide contraseña, bloqueando el hilo
            // principal. Con PARLA_API_KEY la clave viene del entorno y no se toca.
            if let override = ProcessInfo.processInfo.environment["PARLA_API_KEY"],
               !override.isEmpty { return override }
            #endif
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

    /// Si hay clave, sin leerla. La consulta no pide los datos del elemento,
    /// así que el Llavero no tiene que abrirlo ni pedir la contraseña aunque la
    /// app se haya vuelto a firmar. Cualquier fallo cuenta como «no hay clave».
    var hasAPIKey: Bool {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PARLA_API_KEY"],
           !override.isEmpty { return true }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
