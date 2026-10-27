import Testing
import Foundation
import SwiftData
import ParlaCore
@testable import Parla

private func makeStore() throws -> (NotebookStore, ModelContainer) {
    let container = try Persistence.makeContainer(ModelConfiguration(isStoredInMemoryOnly: true))
    return (NotebookStore(modelContainer: container), container)
}

private func line(_ id: UUID, in container: ModelContainer) throws -> NotebookLine? {
    try ModelContext(container)
        .fetch(FetchDescriptor<NotebookLine>(predicate: #Predicate { $0.id == id })).first
}

private let saved = LiveTranslation(
    spanish: "No te preocupes.", save: true,
    expressions: [LiveExpression(phrase: "don't sweat it", meaning: "no te preocupes")])

@Test func elContextoCruzaSesionesDelMismoCuaderno() async throws {
    let (store, _) = try makeStore()
    let notebook = await store.createNotebook(name: "AFK Journey", about: "")
    let first = UUID(), second = UUID()
    for index in 0..<16 {
        await store.insertLine(id: UUID(), english: "Line \(index)",
                               sessionID: index < 8 ? first : second, notebookID: notebook,
                               readAt: Date(timeIntervalSince1970: Double(index)))
    }
    let context = await store.context(notebookID: notebook, sessionID: second)
    #expect(context.recentLines == (4..<16).map { "Line \($0)" })
}

@Test func sinCuadernoElContextoEsSoloDeLaSesion() async throws {
    let (store, _) = try makeStore()
    let session = UUID()
    await store.insertLine(id: UUID(), english: "Other session", sessionID: UUID(),
                           notebookID: nil, readAt: Date(timeIntervalSince1970: 1))
    await store.insertLine(id: UUID(), english: "This session", sessionID: session,
                           notebookID: nil, readAt: Date(timeIntervalSince1970: 2))
    let context = await store.context(notebookID: nil, sessionID: session)
    #expect(context.recentLines == ["This session"])
    #expect(context.about == "")
}

@Test func elContextoLlevaElDeQueTrataDelCuaderno() async throws {
    let (store, _) = try makeStore()
    let notebook = await store.createNotebook(name: "AFK", about: "RPG de fantasía")
    let context = await store.context(notebookID: notebook, sessionID: UUID())
    #expect(context.about == "RPG de fantasía")
}

@Test func aplicarUnaTraduccionConSaveLaGuarda() async throws {
    let (store, container) = try makeStore()
    let id = UUID()
    await store.insertLine(id: id, english: "Don't sweat it.", sessionID: UUID(),
                           notebookID: nil, readAt: .now)
    await store.apply(saved, toLine: id)
    let stored = try #require(try line(id, in: container))
    #expect(stored.spanish == "No te preocupes.")
    #expect(stored.isSaved)
    #expect(stored.expressions.map(\.phrase) == ["don't sweat it"])
}

@Test func aplicarNilLaDejaSinTraducir() async throws {
    let (store, container) = try makeStore()
    let id = UUID()
    await store.insertLine(id: id, english: "???", sessionID: UUID(), notebookID: nil, readAt: .now)
    await store.apply(nil, toLine: id)
    let stored = try #require(try line(id, in: container))
    #expect(stored.spanish == nil)
    #expect(!stored.isSaved)
}

@Test func guardarAManoGuardaConSusExpresiones() async throws {
    let (store, container) = try makeStore()
    let id = UUID()
    await store.insertLine(id: id, english: "Don't sweat it.", sessionID: UUID(),
                           notebookID: nil, readAt: .now)
    await store.apply(LiveTranslation(spanish: "No te preocupes.", save: false, expressions: []),
                      toLine: id)
    #expect(try line(id, in: container)?.isSaved == false)
    await store.save(line: id, with: saved)
    let stored = try #require(try line(id, in: container))
    #expect(stored.isSaved)
    #expect(stored.expressions.count == 1)
    await store.unsave(line: id)
    #expect(try line(id, in: container)?.isSaved == false)
}

@Test func lasVecinasSonDeLaMismaSesion() async throws {
    let (store, _) = try makeStore()
    let session = UUID()
    let middle = UUID()
    await store.insertLine(id: UUID(), english: "Before", sessionID: session,
                           notebookID: nil, readAt: Date(timeIntervalSince1970: 1))
    await store.insertLine(id: UUID(), english: "Intruder", sessionID: UUID(),
                           notebookID: nil, readAt: Date(timeIntervalSince1970: 2))
    await store.insertLine(id: middle, english: "Middle", sessionID: session,
                           notebookID: nil, readAt: Date(timeIntervalSince1970: 3))
    await store.insertLine(id: UUID(), english: "After", sessionID: session,
                           notebookID: nil, readAt: Date(timeIntervalSince1970: 4))
    let neighbors = await store.neighbors(ofLine: middle)
    #expect(neighbors.before == "Before")
    #expect(neighbors.after == "After")
}

@Test func borrarUnCuadernoBorraSusLineas() async throws {
    let (store, container) = try makeStore()
    let notebook = await store.createNotebook(name: "AFK", about: "")
    await store.insertLine(id: UUID(), english: "Hi.", sessionID: UUID(),
                           notebookID: notebook, readAt: .now)
    await store.deleteNotebook(notebook)
    let context = ModelContext(container)
    #expect(try context.fetch(FetchDescriptor<Notebook>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<NotebookLine>()).isEmpty)
}

@Test func renombrarUnCuadernoCambiaNombreYDeQueTrata() async throws {
    let (store, container) = try makeStore()
    let notebook = await store.createNotebook(name: "AFK", about: "")
    await store.updateNotebook(notebook, name: "AFK Journey", about: "RPG")
    let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<Notebook>()).first)
    #expect(stored.name == "AFK Journey")
    #expect(stored.about == "RPG")
}
