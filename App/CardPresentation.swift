import Foundation
import Observation
import ParlaCore

enum CardState: Sendable {
    case pending
    case ready(Card)
    case failed(ExplainerError)
}

@MainActor
@Observable
final class CardPresentation: Identifiable {
    let utterance: Utterance
    var state: CardState

    nonisolated var id: UUID { utterance.id }

    init(utterance: Utterance, state: CardState = .pending) {
        self.utterance = utterance
        self.state = state
    }
}

extension ExplainerError {
    /// Mensaje para el usuario. El rate limit no es un fallo de red y no debe
    /// invitar a reintentar de inmediato.
    var readableMessage: String {
        switch self {
        case .missingAPIKey: "Falta tu clave de la API. Ábrela en Ajustes."
        case .rateLimited:   "Vas muy rápido para la API. Espera unos segundos."
        case .server(let s, let m):
            m.map { "Error \(s): \($0)" } ?? "El servidor respondió \(s). Puedes reintentar."
        case .refused:       "No se pudo traducir esta frase."
        case .malformedResponse: "La respuesta llegó incompleta. Puedes reintentar."
        case .network(let m): "Sin conexión: \(m)"
        }
    }

    var allowsRetry: Bool {
        switch self {
        case .rateLimited, .missingAPIKey, .refused: false
        case .server, .malformedResponse, .network: true
        }
    }
}
