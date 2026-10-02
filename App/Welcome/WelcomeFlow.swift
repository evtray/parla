import ParlaCore

enum WelcomeStep: Int, CaseIterable {
    case hello, key, permissions, ready
}

/// El avance de la bienvenida, sin vista, para poder probarlo.
struct WelcomeFlow: Equatable {
    private(set) var step: WelcomeStep = .hello
    /// Lo que se dice bajo el campo de la clave o, si la clave se guardó sin
    /// comprobar, al principio del paso siguiente.
    private(set) var keyMessage: String?

    var isLast: Bool { step == .ready }

    /// «Ahora no» y «Continuar» en los pasos sin campo.
    mutating func advance() {
        keyMessage = nil
        if let next = WelcomeStep(rawValue: step.rawValue + 1) { step = next }
    }

    /// «Continuar» en el paso de la clave, con lo que respondió `APIKeyEntry`.
    /// `nil` es campo vacío: vale si ya había una clave guardada.
    mutating func keySubmitted(_ check: KeyCheck?, hasSavedKey: Bool) {
        switch check {
        case .valid?:
            advance()
        case .unverified?:
            advance()
            keyMessage = KeyCheck.unverified.message
        case .invalid?:
            keyMessage = KeyCheck.invalid.message
        case nil:
            if hasSavedKey {
                advance()
            } else {
                keyMessage = "Pega tu clave o pulsa «Ahora no»."
            }
        }
    }
}
