import Foundation
import Observation
import ParlaCore

/// De dónde salió la tarjeta. Las dos clases comparten el panel y el orden.
enum CardOrigin: Sendable {
    case voice(Utterance)
    case capture(Capture)
}

enum CardState: Sendable {
    case pending
    case ready(Card)
    case readyCapture(CaptureCard)
    case failed(ExplainerError)
}

@MainActor
@Observable
final class CardPresentation: Identifiable {
    let origin: CardOrigin
    var state: CardState
    /// El caso que el usuario pidió con «¿No era eso?». `nil`: decide el modelo.
    var forcedKind: CaptureKind? = nil

    nonisolated var id: UUID {
        switch origin {
        case .voice(let utterance): utterance.id
        case .capture(let capture): capture.id
        }
    }

    /// Cuándo se dijo la frase o se tomó la captura. Ordena el panel, porque
    /// las respuestas llegan desordenadas.
    nonisolated var date: Date {
        switch origin {
        case .voice(let utterance): utterance.startedAt
        case .capture(let capture): capture.capturedAt
        }
    }

    var utterance: Utterance? {
        if case .voice(let utterance) = origin { return utterance }
        return nil
    }

    var capture: Capture? {
        if case .capture(let capture) = origin { return capture }
        return nil
    }

    init(utterance: Utterance, state: CardState = .pending) {
        self.origin = .voice(utterance)
        self.state = state
    }

    init(capture: Capture, state: CardState = .pending) {
        self.origin = .capture(capture)
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
