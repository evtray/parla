import Testing
import Foundation
@testable import ParlaCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

@Test func noCierraAntesDeQuePaseElSilencio() {
    var seg = UtteranceSegmenter()
    #expect(seg.ingest(.final("hola qué tal"), at: at(0)) == nil)
    #expect(seg.tick(at: at(0.5)) == nil)   // 500 ms < 900 ms
}

@Test func cierraCuandoPasaElSilencio() {
    var seg = UtteranceSegmenter()
    _ = seg.ingest(.final("hola qué tal"), at: at(0))
    let u = seg.tick(at: at(1.0))
    #expect(u?.text == "hola qué tal")
    #expect(u?.startedAt == at(0))
}

@Test func unParcialMantieneVivaLaFrase() {
    var seg = UtteranceSegmenter()
    _ = seg.ingest(.final("necesito que"), at: at(0))
    _ = seg.ingest(.partial("me avi"), at: at(0.8))   // sigues hablando
    #expect(seg.tick(at: at(1.0)) == nil)             // 200 ms desde el parcial
    #expect(seg.tick(at: at(1.8)) != nil)             // 1000 ms desde el parcial
}

@Test func uneVariosFinalesEnUnaSolaFrase() {
    var seg = UtteranceSegmenter()
    _ = seg.ingest(.final("necesito que"), at: at(0))
    _ = seg.ingest(.final("me avises"), at: at(0.4))
    #expect(seg.tick(at: at(1.4))?.text == "necesito que me avises")
}

@Test func elParcialNoEntraEnElTexto() {
    var seg = UtteranceSegmenter()
    _ = seg.ingest(.final("hola"), at: at(0))
    _ = seg.ingest(.partial("basura volátil"), at: at(0.1))
    #expect(seg.tick(at: at(1.1))?.text == "hola")
}

@Test func cortaLasFrasesDemasiadoLargasSinEsperarSilencio() {
    var seg = UtteranceSegmenter(config: .init(maxCharacters: 20))
    #expect(seg.ingest(.final("uno dos tres"), at: at(0)) == nil)
    let u = seg.ingest(.final("cuatro cinco seis"), at: at(0.2))
    #expect(u?.text == "uno dos tres cuatro cinco seis")
}

@Test func descartaRuidoDemasiadoCorto() {
    var seg = UtteranceSegmenter()
    _ = seg.ingest(.final("eh"), at: at(0))
    #expect(seg.tick(at: at(1.0)) == nil)
    // y además deja el buffer limpio para la frase siguiente
    _ = seg.ingest(.final("hola mundo"), at: at(2.0))
    #expect(seg.tick(at: at(3.0))?.text == "hola mundo")
}

@Test func laSegundaFraseEmpiezaConSuPropioReloj() {
    var seg = UtteranceSegmenter()
    _ = seg.ingest(.final("primera"), at: at(0))
    _ = seg.tick(at: at(1.0))
    _ = seg.ingest(.final("segunda"), at: at(5.0))
    #expect(seg.tick(at: at(6.0))?.startedAt == at(5.0))
}

@Test func tickSobreBufferVacioNoHaceNada() {
    var seg = UtteranceSegmenter()
    #expect(seg.tick(at: at(99)) == nil)
}
