import Testing
import ParlaCore
@testable import Parla

@Test func unModoApagadoEnsenaSuAtajo() {
    let tile = ModeTileModel(mode: .capture, isActive: false, shortcut: "⌃⌥C")
    #expect(tile.title == "Captura")
    #expect(tile.caption == "⌃⌥C")
}

@Test func laVozEncendidaDiceEscuchando() {
    let tile = ModeTileModel(mode: .voice, isActive: true, shortcut: "⌃⌥Space")
    #expect(tile.caption == "Escuchando")
    #expect(tile.symbol == "mic.fill")
}

@Test func losSubtitulosEncendidosDicenActivos() {
    let tile = ModeTileModel(mode: .subtitles, isActive: true, shortcut: "⌃⌥S")
    #expect(tile.caption == "Activos")
    #expect(tile.symbol == "captions.bubble.fill")
}

@Test func sinAtajoLoDice() {
    #expect(ModeTileModel(mode: .voice, isActive: false, shortcut: nil).caption == "Sin atajo")
}
