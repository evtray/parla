import Foundation

public struct VocabTerm: Sendable, Equatable, Codable {
    public let term: String
    public let meaning: String

    public init(term: String, meaning: String) {
        self.term = term
        self.meaning = meaning
    }
}

/// Lo que Claude devuelve para una frase. La forma coincide con el json_schema
/// que se envía en `output_config.format`, así que se decodifica directo.
public struct Card: Sendable, Equatable, Codable {
    public let english: String
    public let why: [String]
    public let vocab: [VocabTerm]
    /// `true` cuando la entrada no era una frase (ruido, muletilla, palabra cortada).
    public let skip: Bool

    public init(english: String, why: [String], vocab: [VocabTerm], skip: Bool) {
        self.english = english
        self.why = why
        self.vocab = vocab
        self.skip = skip
    }
}
