import Testing
import Foundation
import ParlaCore
@testable import Parla

private func card(origin: String, kind: String? = nil,
                  source: String = "original", result: String = "resultado") -> StoredCard {
    StoredCard(id: UUID(), source: source, result: result, why: [], createdAt: Date(),
               origin: origin, kind: kind, vocab: [])
}

@Test func enLaVozElInglesEsElResultado() {
    #expect(EnglishSide(origin: "voice", kind: nil) == .result)
}

@Test func enLosSubtitulosElInglesEsElOriginal() {
    #expect(EnglishSide(origin: "system", kind: nil) == .source)
}

@Test func enUnaCapturaDependeDelCaso() {
    #expect(EnglishSide(origin: "screen", kind: "understand") == .source)
    #expect(EnglishSide(origin: "screen", kind: "translate") == .result)
    #expect(EnglishSide(origin: "screen", kind: "correct") == .both)
    #expect(EnglishSide(origin: "screen", kind: "skip") == .source)
    #expect(EnglishSide(origin: "screen", kind: nil) == .source)
}

@Test func copiarElInglesDeUnaCorreccionCopiaLaVersionCorregida() {
    let corrected = card(origin: "screen", kind: "correct",
                         source: "I has a question", result: "I have a question")
    #expect(corrected.englishText == "I have a question")
    #expect(corrected.otherText == "I has a question")
}

@Test func copiarElInglesDeUnSubtituloCopiaElOriginal() {
    let line = card(origin: "system", source: "Welcome back", result: "Bienvenidos")
    #expect(line.englishText == "Welcome back")
    #expect(line.otherText == "Bienvenidos")
}

@Test func enLaVozElOtroLadoEsLoQueDijiste() {
    let spoken = card(origin: "voice", source: "me da igual", result: "I don't mind.")
    #expect(spoken.englishText == "I don't mind.")
    #expect(spoken.otherText == "me da igual")
}

private func capture(_ kind: CaptureKind) -> CaptureCard {
    CaptureCard(kind: kind, source: "original", result: "resultado", why: [], vocab: [])
}

@Test func escucharUnaCapturaLeeElLadoEnIngles() {
    #expect(capture(.understand).englishText == "original")
    #expect(capture(.translate).englishText == "resultado")
    // En una corrección se oye la versión corregida, no el borrador.
    #expect(capture(.correct).englishText == "resultado")
}
