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
    #expect(stored[0].source == "necesito que me avises")
    #expect(stored[0].result == "I need you to let me know.")
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

private func memoryStore() throws -> (CardStore, ModelContainer) {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return (CardStore(modelContainer: container), container)
}

private let capture = Capture(imageData: Data([1]), mediaType: "image/png",
                              capturedAt: Date(timeIntervalSince1970: 99))

private func captureCard(_ kind: CaptureKind) -> CaptureCard {
    CaptureCard(kind: kind, source: "I am agree", result: "I agree.",
                why: ["\"Agree\" ya es verbo."],
                vocab: [VocabTerm(term: "agree", meaning: "estar de acuerdo")])
}

@Test func guardaUnaCapturaConSuCasoYSuOrigen() async throws {
    let (store, container) = try memoryStore()
    await store.save(capture: capture, card: captureCard(.correct))

    let stored = try ModelContext(container).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.id == capture.id)
    #expect(stored.first?.origin == "screen")
    #expect(stored.first?.kind == "correct")
    #expect(stored.first?.source == "I am agree")
    #expect(stored.first?.createdAt == Date(timeIntervalSince1970: 99))
    #expect(stored.first?.vocab.first?.meaning == "estar de acuerdo")
}

@Test func reclasificarVariasVecesDejaUnaSolaFila() async throws {
    let (store, container) = try memoryStore()
    await store.save(capture: capture, card: captureCard(.correct))
    await store.save(capture: capture, card: captureCard(.understand))
    await store.save(capture: capture, card: captureCard(.translate))

    let stored = try ModelContext(container).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.kind == "translate")
}

@Test func unSkipNoVaAlHistorial() async throws {
    let (store, container) = try memoryStore()
    await store.save(capture: capture,
                     card: CaptureCard(kind: .skip, source: "", result: "", why: [], vocab: []))
    #expect(try ModelContext(container).fetch(FetchDescriptor<StoredCard>()).isEmpty)
}

@Test func borrarUnaTarjetaBorraSuVocabulario() throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    context.insert(StoredCard(id: UUID(), source: "me da igual", result: "I don't mind.",
                              why: [], createdAt: Date(),
                              vocab: [StoredVocab(term: "mind", meaning: "importar")]))
    try context.save()

    let card = try #require(try context.fetch(FetchDescriptor<StoredCard>()).first)
    context.delete(card)
    try context.save()

    #expect(try context.fetch(FetchDescriptor<StoredCard>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<StoredVocab>()).isEmpty)
}

@Test func marcarFavoritaSobreviveAGuardar() throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let card = StoredCard(id: UUID(), source: "hola", result: "hello", why: [],
                          createdAt: Date(), vocab: [])
    context.insert(card)
    #expect(!card.isFavorite)
    card.isFavorite = true
    try context.save()

    let fresh = ModelContext(container)
    #expect(try fresh.fetch(FetchDescriptor<StoredCard>()).first?.isFavorite == true)
}
