import Foundation

/// Una frase cerrada, lista para traducir.
public struct Utterance: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    /// Momento del primer sonido de la frase. Ordena las tarjetas en el panel,
    /// porque las respuestas de la API pueden llegar desordenadas.
    public let startedAt: Date

    public init(id: UUID = UUID(), text: String, startedAt: Date) {
        self.id = id
        self.text = text
        self.startedAt = startedAt
    }
}
