import Testing
@testable import ParlaCore

@Test func elTextoQueApareceLetraPorLetraSaleUnaVez() {
    var detector = LineDetector()
    #expect(detector.feed("The Gl") == nil)
    #expect(detector.feed("The Gloomwood") == nil)
    #expect(detector.feed("The Gloomwood stirs again.") == nil)
    #expect(detector.feed("The Gloomwood stirs again.") == "The Gloomwood stirs again.")
    #expect(detector.feed("The Gloomwood stirs again.") == nil)
}

@Test func unaLetraMalLeidaNoRepiteLaLinea() {
    var detector = LineDetector()
    _ = detector.feed("We have to hold the line until dawn.")
    #expect(detector.feed("We have to hold the line until dawn.") != nil)
    #expect(detector.feed("We have to hold the Iine until dawn.") == nil)
    #expect(detector.feed("We have to hold the Iine until dawn.") == nil)
}

@Test func unaFraseRepetidaConOtraEnMedioSaleDosVeces() {
    var detector = LineDetector()
    let a = "Stay close to me.", b = "The bridge is out."
    _ = detector.feed(a)
    #expect(detector.feed(a) == a)
    _ = detector.feed(b)
    #expect(detector.feed(b) == b)
    _ = detector.feed(a)
    #expect(detector.feed(a) == a)
}

@Test func unRecuadroVacioPermiteRepetirLaFrase() {
    var detector = LineDetector()
    let a = "Stay close to me."
    _ = detector.feed(a)
    #expect(detector.feed(a) == a)
    #expect(detector.feed("") == nil)
    _ = detector.feed(a)
    #expect(detector.feed(a) == a)
}

@Test func forceSueltaAunqueSeRepita() {
    var detector = LineDetector()
    let a = "Stay close to me."
    _ = detector.feed(a)
    _ = detector.feed(a)
    #expect(detector.force(a) == a)
    #expect(detector.force("  ") == nil)
}

@Test func losBordesNoCuentan() {
    #expect(LineDetector.normalize("| Hello   there _") == "Hello there")
}
