import Testing
import Foundation
@testable import ParlaCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private let card = Card(english: "I need you to let me know.",
                        why: ["porque sí"],
                        vocab: [],
                        skip: false)

@Test func convierteHablaEnTarjetas() async throws {
    let transcriber = FakeTranscriber(script: [
        (.partial("necesito"),            t0),
        (.final("necesito que me avises"), t0.addingTimeInterval(0.3)),
        // el silencio se simula con un evento tardío que dispara el tick
        (.final("y ya está"),              t0.addingTimeInterval(5.0)),
    ])
    let pipeline = SessionPipeline(transcriber: transcriber,
                                   explainer: FakeExplainer(result: .success(card)))

    var cards: [(Utterance, Card)] = []
    for await output in pipeline.outputs {
        if case .card(let u, let c) = output { cards.append((u, c)) }
    }
    // Las frases se explican en paralelo, así que el orden de llegada no es
    // determinista: se ordena por cuándo se dijo cada una, como hace el panel.
    cards.sort { $0.0.startedAt < $1.0.startedAt }

    #expect(cards.count == 2)
    #expect(cards[0].0.text == "necesito que me avises")
    #expect(cards[0].1.english == "I need you to let me know.")
    #expect(cards[1].0.text == "y ya está")
}

@Test func emiteLosParcialesParaQueElPanelLosPinte() async {
    let transcriber = FakeTranscriber(script: [
        (.partial("nece"), t0),
        (.partial("necesito"), t0.addingTimeInterval(0.1)),
    ])
    let pipeline = SessionPipeline(transcriber: transcriber,
                                   explainer: FakeExplainer(result: .success(nil)))

    var partials: [String] = []
    for await output in pipeline.outputs {
        if case .partial(let text) = output { partials.append(text) }
    }
    #expect(partials == ["nece", "necesito"])
}

@Test func noEmiteTarjetaCuandoElModeloMarcaSkip() async {
    let transcriber = FakeTranscriber(script: [
        (.final("eh bueno"), t0),
        (.final("cierre"), t0.addingTimeInterval(5.0)),
    ])
    let pipeline = SessionPipeline(transcriber: transcriber,
                                   explainer: FakeExplainer(result: .success(nil)))

    var cards = 0
    for await output in pipeline.outputs {
        if case .card = output { cards += 1 }
    }
    #expect(cards == 0)
}

@Test func propagaElErrorConLaFraseQueLoCauso() async {
    let transcriber = FakeTranscriber(script: [
        (.final("hola mundo"), t0),
        (.final("cierre"), t0.addingTimeInterval(5.0)),
    ])
    let pipeline = SessionPipeline(
        transcriber: transcriber,
        explainer: FakeExplainer(result: .failure(.rateLimited)))

    var failures: [(Utterance, ExplainerError)] = []
    for await output in pipeline.outputs {
        if case .failure(let u, let e) = output { failures.append((u, e)) }
    }
    #expect(failures.count == 2)
    #expect(failures.contains { $0.0.text == "hola mundo" })
    #expect(failures.allSatisfy { $0.1 == .rateLimited })
}
