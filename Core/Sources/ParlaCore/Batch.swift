import Foundation

/// Lo que el modelo devuelve cuando se le mandan varias frases de una vez.
/// La forma coincide con el `json_schema` del lote, así que se decodifica directo.
public struct BatchResponse: Sendable, Equatable, Codable {

    /// Una tarjeta con el número de la frase a la que responde.
    ///
    /// El índice es explícito y no posicional: si el modelo se salta una
    /// entrada, las demás siguen apuntando a su frase en vez de correrse todas
    /// un puesto, que es como una respuesta incompleta se convierte en veinte
    /// tarjetas mal emparejadas.
    public struct Entry: Sendable, Equatable, Codable {
        public let index: Int
        public let english: String
        public let why: [String]
        public let vocab: [VocabTerm]
        public let skip: Bool

        public var card: Card {
            Card(english: english, why: why, vocab: vocab, skip: skip)
        }
    }

    public let cards: [Entry]
    /// Patrones del lote entero. Vacío si no hay ninguno que destacar.
    public let summary: [String]
}

/// Una frase que se quedó sin respuesta, con el motivo.
public struct BatchFailure: Sendable, Equatable {
    public let utterance: Utterance
    public let error: ExplainerError

    public init(utterance: Utterance, error: ExplainerError) {
        self.utterance = utterance
        self.error = error
    }
}

/// El resultado de explicar un lote.
///
/// Una frase acaba en exactamente uno de tres sitios: `cards` si tiene tarjeta,
/// `failures` si no hubo respuesta para ella, y en ninguno si el modelo la
/// descartó por no ser una frase. La ausencia silenciosa es deliberada: el
/// ruido no merece ni tarjeta ni aviso.
public struct BatchOutcome: Sendable, Equatable {
    public let cards: [Utterance.ID: Card]
    public let summary: [String]
    public let failures: [BatchFailure]

    public init(cards: [Utterance.ID: Card],
                summary: [String],
                failures: [BatchFailure]) {
        self.cards = cards
        self.summary = summary
        self.failures = failures
    }
}
