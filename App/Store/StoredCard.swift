import Foundation
import SwiftData
import ParlaCore

@Model
final class StoredCard {
    var id: UUID
    var spanish: String
    var english: String
    var why: [String]
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var vocab: [StoredVocab]

    init(id: UUID, spanish: String, english: String,
         why: [String], createdAt: Date, vocab: [StoredVocab]) {
        self.id = id
        self.spanish = spanish
        self.english = english
        self.why = why
        self.createdAt = createdAt
        self.vocab = vocab
    }

    convenience init(utterance: Utterance, card: Card) {
        self.init(id: utterance.id,
                  spanish: utterance.text,
                  english: card.english,
                  why: card.why,
                  createdAt: utterance.startedAt,
                  vocab: card.vocab.map { StoredVocab(term: $0.term, meaning: $0.meaning) })
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
