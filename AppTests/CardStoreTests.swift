import Testing
import Foundation
import SwiftData
import ParlaCore
@testable import Parla

@Test func guardaLaTarjetaConSuVocabulario() async throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = CardStore(modelContainer: container)

    let utterance = Utterance(text: "necesito que me avises",
                              startedAt: Date(timeIntervalSince1970: 42))
    let card = Card(english: "I need you to let me know.",
                    why: ["\"Avisar\" no es \"advise\"."],
                    vocab: [VocabTerm(term: "let me know", meaning: "avisar")],
                    skip: false)

    await store.save(utterance: utterance, card: card)

    let context = ModelContext(container)
    let stored = try context.fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored[0].spanish == "necesito que me avises")
    #expect(stored[0].english == "I need you to let me know.")
    #expect(stored[0].why.count == 1)
    #expect(stored[0].vocab.first?.meaning == "avisar")
    #expect(stored[0].createdAt == Date(timeIntervalSince1970: 42))
}

@Test func laFechaGuardadaEsLaDeLaFraseNoLaDelGuardado() async throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = CardStore(modelContainer: container)
    let spoken = Date(timeIntervalSince1970: 1000)

    await store.save(utterance: Utterance(text: "hola mundo", startedAt: spoken),
                     card: Card(english: "hello world", why: ["x"], vocab: [], skip: false))

    let stored = try ModelContext(container).fetch(FetchDescriptor<StoredCard>())
    #expect(stored[0].createdAt == spoken)
}
