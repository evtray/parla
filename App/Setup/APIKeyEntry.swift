import Foundation
import Observation
import ParlaCore

/// El campo de la clave, compartido por la bienvenida y Ajustes: los dos
/// comprueban y guardan igual.
@MainActor
@Observable
final class APIKeyEntry {
    var text = ""
    private(set) var message: String?
    private(set) var isChecking = false

    @ObservationIgnored private let validator: APIKeyValidator
    @ObservationIgnored private let save: @MainActor (String) -> Void

    init(validator: APIKeyValidator = APIKeyValidator(),
         save: @escaping @MainActor (String) -> Void = { KeychainStore.shared.apiKey = $0 }) {
        self.validator = validator
        self.save = save
    }

    /// `nil` si el campo estaba vacío: no hay nada que comprobar, y guardar una
    /// cadena vacía borraría la clave que ya hay.
    @discardableResult
    func submit() async -> KeyCheck? {
        let key = APIKeyValidator.normalize(text)
        guard !key.isEmpty else {
            message = nil
            return nil
        }
        isChecking = true
        let check = await validator.check(key)
        isChecking = false
        message = check.message
        if check.shouldSave {
            save(key)
            text = ""
        }
        return check
    }
}

extension KeyCheck {
    var message: String {
        switch self {
        case .valid: "Clave guardada."
        case .unverified: "No se pudo comprobar la clave; se guardó igualmente."
        case .invalid: "Esa clave no funciona. Revisa que esté completa."
        }
    }
}
