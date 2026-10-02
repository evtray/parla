import Testing
import Foundation
import SwiftData
import ParlaCore
@testable import Parla

@Test func cadaFiltroDejaPasarSuOrigen() {
    #expect(HistoryFilter.all.includes(origin: "system"))
    #expect(HistoryFilter.voice.includes(origin: "voice"))
    #expect(!HistoryFilter.voice.includes(origin: "screen"))
    #expect(HistoryFilter.screen.includes(origin: "screen"))
    #expect(HistoryFilter.system.includes(origin: "system"))
    #expect(!HistoryFilter.system.includes(origin: "voice"))
}

@Test func losFiltrosSeLlamanComoEnLaInterfaz() {
    #expect(HistoryFilter.allCases.map(\.label) == ["Todo", "Voz", "Capturas", "Subtítulos"])
}

@Test func guardaUnaFraseDeSubtitulos() async throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = CardStore(modelContainer: container)
    await store.save(subtitle: SubtitleLine(english: "Welcome back", spanish: "Bienvenidos",
                                            spokenAt: Date(timeIntervalSince1970: 5)))

    let stored = try ModelContext(container).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.origin == "system")
    #expect(stored.first?.source == "Welcome back")
    #expect(stored.first?.result == "Bienvenidos")
    #expect(stored.first?.why.isEmpty == true)
    #expect(stored.first?.createdAt == Date(timeIntervalSince1970: 5))
}
