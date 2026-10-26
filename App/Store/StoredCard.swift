import Foundation
import SwiftData
import ParlaCore

@Model
final class StoredCard {
    var id: UUID
    /// Lo que se dijo o lo que se leyó en la captura. El nombre antiguo
    /// (`spanish`) mentía en cuanto una captura en inglés lo llenaba.
    @Attribute(originalName: "spanish") var source: String
    /// La traducción, la corrección o el inglés.
    @Attribute(originalName: "english") var result: String
    var why: [String]
    var createdAt: Date
    /// `"voice"` o `"screen"`. Con valor por defecto para que las filas
    /// antiguas migren solas.
    var origin: String = "voice"
    /// `CaptureKind.rawValue`; `nil` en las tarjetas de voz.
    var kind: String?
    @Relationship(deleteRule: .cascade) var vocab: [StoredVocab]

    init(id: UUID, source: String, result: String, why: [String], createdAt: Date,
         origin: String = "voice", kind: String? = nil, vocab: [StoredVocab]) {
        self.id = id
        self.source = source
        self.result = result
        self.why = why
        self.createdAt = createdAt
        self.origin = origin
        self.kind = kind
        self.vocab = vocab
    }

    convenience init(utterance: Utterance, card: Card) {
        self.init(id: utterance.id,
                  source: utterance.text,
                  result: card.english,
                  why: card.why,
                  createdAt: utterance.startedAt,
                  vocab: card.vocab.map { StoredVocab(term: $0.term, meaning: $0.meaning) })
    }

    convenience init(capture: Capture, card: CaptureCard) {
        self.init(id: capture.id,
                  source: card.source,
                  result: card.result,
                  why: card.why,
                  createdAt: capture.capturedAt,
                  origin: "screen",
                  kind: card.kind.rawValue,
                  vocab: card.vocab.map { StoredVocab(term: $0.term, meaning: $0.meaning) })
    }

    convenience init(subtitle: SubtitleLine) {
        self.init(id: UUID(),
                  source: subtitle.english,
                  result: subtitle.spanish,
                  why: [],
                  createdAt: subtitle.spokenAt,
                  origin: "system",
                  vocab: [])
    }
}

@Model
final class StoredVocab {
    var term: String
    var meaning: String

    init(term: String, meaning: String) {
        self.term = term
        self.meaning = meaning
    }
}
