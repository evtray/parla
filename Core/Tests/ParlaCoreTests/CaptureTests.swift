import Testing
import Foundation
@testable import ParlaCore

@Test func laTarjetaDeCapturaSeDecodificaDelEsquema() throws {
    let json = #"{"kind":"understand","source":"Heads up","result":"Ojo","#
        + #""why":["x"],"vocab":[{"term":"heads up","meaning":"ojo"}]}"#
    let card = try JSONDecoder().decode(CaptureCard.self, from: Data(json.utf8))
    #expect(card.kind == .understand)
    #expect(card.result == "Ojo")
    #expect(card.vocab.first?.term == "heads up")
}

@Test func unCasoDesconocidoNoSeDecodifica() {
    // Si el modelo inventara un caso, la tarjeta no puede pintarse: mejor fallar
    // aquí que mostrar algo sin etiqueta.
    let json = #"{"kind":"summarize","source":"","result":"","why":[],"vocab":[]}"#
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CaptureCard.self, from: Data(json.utf8))
    }
}

@Test func losCasosVanEnElOrdenDelEsquema() {
    #expect(CaptureKind.allCases.map(\.rawValue)
            == ["understand", "correct", "translate", "skip"])
}

@Test func elPromptDeCapturaEsLoBastanteLargoParaCachearse() {
    // Mismo margen que el de la voz: muy por encima del mínimo cacheable.
    #expect(CaptureSystemPrompt.text.count > 4000)
}

@Test func elPromptDeCapturaNombraLosCuatroCasos() {
    for kind in CaptureKind.allCases {
        #expect(CaptureSystemPrompt.text.contains(kind.rawValue))
    }
}
