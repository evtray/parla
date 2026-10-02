import Testing
import Foundation
import SwiftData
@testable import Parla

/// El esquema tal como estaba antes de la captura. Anidado en un
/// `VersionedSchema` para que la entidad se siga llamando `StoredCard`.
enum LegacySchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredCard.self, StoredVocab.self] }

    @Model
    final class StoredCard {
        var id: UUID
        var spanish: String
        var english: String
        var why: [String]
        var createdAt: Date
        @Relationship(deleteRule: .cascade) var vocab: [StoredVocab]

        init(id: UUID, spanish: String, english: String, why: [String],
             createdAt: Date, vocab: [StoredVocab]) {
            self.id = id
            self.spanish = spanish
            self.english = english
            self.why = why
            self.createdAt = createdAt
            self.vocab = vocab
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
}

@Test func unaBaseConElEsquemaAnteriorConservaSusTarjetas() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "parla-migracion-\(UUID().uuidString).store")

    do {
        let legacy = try ModelContainer(for: Schema(versionedSchema: LegacySchema.self),
                                        configurations: ModelConfiguration(url: url))
        let context = ModelContext(legacy)
        context.insert(LegacySchema.StoredCard(
            id: UUID(), spanish: "me da igual", english: "I don't mind.",
            why: ["\"Me da igual\" no se traduce literal."],
            createdAt: Date(timeIntervalSince1970: 7),
            vocab: [LegacySchema.StoredVocab(term: "either way", meaning: "de cualquier forma")]))
        try context.save()
    }

    let current = try Persistence.makeContainer(ModelConfiguration(url: url))
    let stored = try ModelContext(current).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.source == "me da igual")
    #expect(stored.first?.result == "I don't mind.")
    #expect(stored.first?.origin == "voice")
    #expect(stored.first?.kind == nil)
    #expect(stored.first?.vocab.first?.term == "either way")
}
