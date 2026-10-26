import Foundation

public enum ExplainerError: Error, Equatable, Sendable {
    /// No hay API key configurada. La UI invita a abrir Ajustes.
    case missingAPIKey
    /// 429. Mensaje distinto al de red: no ofrecer reintento inmediato.
    case rateLimited
    /// El mensaje viene del cuerpo de la respuesta: sin él, un 400 es indepurable.
    case server(status: Int, message: String?)
    /// La cadena de fallback también declinó la frase.
    case refused
    /// El stream terminó sin JSON válido.
    case malformedResponse
    case network(String)
}

public protocol Explainer: Sendable {
    /// Devuelve `nil` cuando la frase no merecía tarjeta (`skip`).
    func explain(_ utterance: Utterance) async throws -> Card?

    /// Explica varias frases en una sola petición y añade los patrones que se
    /// repiten entre ellas. Lanza solo si ni siquiera se puede intentar (falta
    /// la clave); lo que falle a mitad de camino viaja en `failures`.
    func explainBatch(_ utterances: [Utterance]) async throws -> BatchOutcome
}
