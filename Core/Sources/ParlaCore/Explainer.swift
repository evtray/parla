import Foundation

public enum ExplainerError: Error, Equatable, Sendable {
    /// No hay API key configurada. La UI invita a abrir Ajustes.
    case missingAPIKey
    /// 429. Mensaje distinto al de red: no ofrecer reintento inmediato.
    case rateLimited
    case server(status: Int)
    /// La cadena de fallback también declinó la frase.
    case refused
    /// El stream terminó sin JSON válido.
    case malformedResponse
    case network(String)
}

public protocol Explainer: Sendable {
    /// Devuelve `nil` cuando la frase no merecía tarjeta (`skip`).
    func explain(_ utterance: Utterance) async throws -> Card?
}
