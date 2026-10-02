import Testing
@testable import Parla

@Test func avisaSoloCuandoFaltaAlgo() {
    #expect(LiveTranslator.notice(for: .ready) == nil)
    #expect(LiveTranslator.notice(for: .needsLanguages)?.contains("Idiomas de traducción") == true)
    #expect(LiveTranslator.notice(for: .unsupported) != nil)
}
