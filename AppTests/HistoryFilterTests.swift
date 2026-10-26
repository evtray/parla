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

@Test func laEstrellaSeCombinaConElModo() {
    #expect(HistoryFilter.voice.includes(origin: "voice", isFavorite: true, favoritesOnly: true))
    #expect(!HistoryFilter.voice.includes(origin: "voice", isFavorite: false, favoritesOnly: true))
    #expect(!HistoryFilter.voice.includes(origin: "screen", isFavorite: true, favoritesOnly: true))
    #expect(HistoryFilter.all.includes(origin: "system", isFavorite: true, favoritesOnly: true))
    #expect(HistoryFilter.all.includes(origin: "system", isFavorite: false, favoritesOnly: false))
}

@Test func cadaOrigenTieneSuIconoYSuNombre() {
    #expect(CardOriginStyle.symbol(origin: "voice") == "mic")
    #expect(CardOriginStyle.symbol(origin: "screen") == "crop")
    #expect(CardOriginStyle.symbol(origin: "system") == "captions.bubble")
    #expect(CardOriginStyle.name(origin: "voice", kind: nil) == "Voz")
    #expect(CardOriginStyle.name(origin: "system", kind: nil) == "Subtítulos")
    #expect(CardOriginStyle.name(origin: "screen", kind: "correct") == "Corrección")
    #expect(CardOriginStyle.name(origin: "screen", kind: nil) == "Captura")
}

@Test func losCasosDeCapturaTienenNombreSinIcono() {
    #expect(CaptureKind.allCases.map(\.title)
            == ["Para entender", "Corrección", "Traducción", "Sin texto"])
}
