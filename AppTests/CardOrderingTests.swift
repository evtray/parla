import Testing
import Foundation
import ParlaCore
@testable import Parla

@MainActor
private func presentation(_ text: String, at seconds: TimeInterval) -> CardPresentation {
    CardPresentation(utterance: Utterance(text: text,
                                          startedAt: Date(timeIntervalSince1970: seconds)))
}

@Test @MainActor func laMasRecienteVaPrimero() {
    let cards = [presentation("primera", at: 10),
                 presentation("segunda", at: 20),
                 presentation("tercera", at: 30)]
    #expect(AppState.mostRecent(cards).map(\.utterance.text)
            == ["tercera", "segunda", "primera"])
}

@Test @MainActor func ordenaPorCuandoSeDijoNoPorCuandoLlego() {
    // Las llamadas a la API se resuelven desordenadas: si la frase antigua
    // vuelve más tarde, no debe colarse arriba.
    let cards = [presentation("tardía pero antigua", at: 10),
                 presentation("reciente", at: 50)]
    #expect(AppState.mostRecent(cards).first?.utterance.text == "reciente")
}

@Test @MainActor func recortaALasTresMasRecientes() {
    let cards = (1...6).map { presentation("f\($0)", at: TimeInterval($0)) }
    let visible = AppState.mostRecent(cards)
    #expect(visible.count == 3)
    #expect(visible.map(\.utterance.text) == ["f6", "f5", "f4"])
}
