import Testing
import Foundation
@testable import ParlaCore

private let t0 = Date(timeIntervalSince1970: 1000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

/// Las traducciones que pidió una lista de acciones.
private func requests(_ actions: [SubtitleState.Action]) -> [SubtitleState.Request] {
    actions.compactMap { if case .translate(let request) = $0 { request } else { nil } }
}

private func outputs(_ actions: [SubtitleState.Action]) -> [SubtitleOutput] {
    actions.compactMap { if case .output(let output) = $0 { output } else { nil } }
}

private func frame(_ actions: [SubtitleState.Action]) -> SubtitleFrame? {
    outputs(actions).compactMap { if case .show(let frame) = $0 { frame } else { nil } }.last
}

@Test func elPrimerParcialSeTraduceAlMomento() {
    var state = SubtitleState()
    let sent = requests(state.ingest(.partial("hello"), at: at(0)))
    #expect(sent == [.init(id: 0, line: 0, text: "hello", isFinal: false)])
}

@Test func dosParcialesSeguidosDanUnaSolaTraduccionLaDelUltimo() {
    var state = SubtitleState()
    _ = state.ingest(.partial("hello"), at: at(0))
    #expect(requests(state.ingest(.partial("hello there"), at: at(0.1))).isEmpty)
    #expect(requests(state.tick(at: at(0.2))).isEmpty)
    let sent = requests(state.tick(at: at(0.26)))
    #expect(sent.map(\.text) == ["hello there"])
    // Ya enviado: el siguiente latido no lo repite.
    #expect(requests(state.tick(at: at(0.6))).isEmpty)
}

@Test func unParcialALos300msSeTraduceDirecto() {
    var state = SubtitleState()
    _ = state.ingest(.partial("hello"), at: at(0))
    #expect(requests(state.ingest(.partial("hello there"), at: at(0.3))).map(\.text)
            == ["hello there"])
}

@Test func elFinalSeTraduceAunqueAcabeDeTraducirseUnParcial() {
    var state = SubtitleState()
    _ = state.ingest(.partial("hello"), at: at(0))
    let sent = requests(state.ingest(.final("hello world"), at: at(0.01)))
    #expect(sent == [.init(id: 1, line: 0, text: "hello world", isFinal: true)])
}

@Test func elFinalReemplazaAlParcialYLuegoPasaArriba() {
    var state = SubtitleState()
    let partial = requests(state.ingest(.partial("hello"), at: at(0)))[0]
    #expect(frame(state.receive(partial, translation: "hola"))
            == SubtitleFrame(previous: nil, current: "hola",
                             currentIsFinal: false, currentIsOriginal: false))

    let final = requests(state.ingest(.final("hello world"), at: at(1)))[0]
    let afterFinal = state.receive(final, translation: "hola mundo")
    #expect(outputs(afterFinal).contains(.line(SubtitleLine(
        english: "hello world", spanish: "hola mundo", spokenAt: at(0)))))
    #expect(frame(afterFinal)?.current == "hola mundo")
    #expect(frame(afterFinal)?.currentIsFinal == true)

    let next = requests(state.ingest(.partial("and you"), at: at(2)))[0]
    #expect(next.line == 1)
    #expect(frame(state.receive(next, translation: "y tú"))
            == SubtitleFrame(previous: "hola mundo", current: "y tú",
                             currentIsFinal: false, currentIsOriginal: false))
}

@Test func cadaFinalSeGuardaUnaSolaVez() {
    var state = SubtitleState()
    let final = requests(state.ingest(.final("hello"), at: at(0)))[0]
    let first = outputs(state.receive(final, translation: "hola"))
    let second = outputs(state.receive(final, translation: "hola"))
    #expect(first.filter { if case .line = $0 { true } else { false } }.count == 1)
    #expect(!second.contains { if case .line = $0 { true } else { false } })
}

@Test func unaTraduccionTardiaNoPisaAUnaMasNueva() {
    var state = SubtitleState()
    let old = requests(state.ingest(.partial("hel"), at: at(0)))[0]
    let new = requests(state.ingest(.partial("hello there"), at: at(0.3)))[0]
    #expect(frame(state.receive(new, translation: "hola, tú"))?.current == "hola, tú")
    #expect(frame(state.receive(old, translation: "hol")) == nil)
}

@Test func siLaTraduccionFallaSeVeElIngles() {
    var state = SubtitleState()
    let final = requests(state.ingest(.final("break a leg"), at: at(0)))[0]
    let actions = state.receive(final, translation: nil)
    #expect(outputs(actions).contains(.line(SubtitleLine(
        english: "break a leg", spanish: "", spokenAt: at(0)))))
    #expect(frame(actions) == SubtitleFrame(previous: nil, current: "break a leg",
                                            currentIsFinal: true, currentIsOriginal: true))
}

@Test func cuatroSegundosDeSilencioOcultanLaBanda() {
    var state = SubtitleState()
    let final = requests(state.ingest(.final("hello"), at: at(0)))[0]
    _ = state.receive(final, translation: "hola")
    #expect(outputs(state.tick(at: at(3.9))).isEmpty)
    #expect(outputs(state.tick(at: at(4))) == [.hide])
    #expect(outputs(state.tick(at: at(5))).isEmpty)   // una sola vez

    // Al volver, la frase de antes de la pausa no reaparece arriba.
    let next = requests(state.ingest(.partial("welcome back"), at: at(60)))[0]
    #expect(frame(state.receive(next, translation: "bienvenidos de nuevo"))?.previous == nil)
}

@Test func pausarAMitadDeFraseTambienOculta() {
    var state = SubtitleState()
    let partial = requests(state.ingest(.partial("so the next"), at: at(0)))[0]
    _ = state.receive(partial, translation: "así que el siguiente")
    #expect(outputs(state.tick(at: at(4.1))) == [.hide])
}

@Test func unFinalVacioSeIgnora() {
    var state = SubtitleState()
    #expect(state.ingest(.final("   "), at: at(0)).isEmpty)
}

@Test func elFinalDeLaFraseAnteriorLlegaTardeYSubeArriba() {
    var state = SubtitleState()
    let first = requests(state.ingest(.final("first one"), at: at(0)))[0]
    let second = requests(state.ingest(.partial("second"), at: at(0.5)))[0]
    #expect(frame(state.receive(second, translation: "segunda"))?.previous == nil)

    let late = state.receive(first, translation: "la primera")
    #expect(outputs(late).contains(.line(SubtitleLine(
        english: "first one", spanish: "la primera", spokenAt: at(0)))))
    #expect(frame(late) == SubtitleFrame(previous: "la primera", current: "segunda",
                                         currentIsFinal: false, currentIsOriginal: false))
}
