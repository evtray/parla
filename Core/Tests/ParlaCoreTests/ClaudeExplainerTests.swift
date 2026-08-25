import Testing
import Foundation
@testable import ParlaCore

private let utterance = Utterance(text: "necesito que me avises",
                                  startedAt: Date(timeIntervalSince1970: 0))

private let cardJSON = """
{"english":"I need you to let me know.",\
"why":["\\"Avisar\\" es \\"let me know\\", no \\"advise\\"."],\
"vocab":[{"term":"let me know","meaning":"avisar"}],\
"skip":false}
"""

private func explainer(_ streamer: any HTTPStreamer, apiKey: String = "sk-test") -> ClaudeExplainer {
    ClaudeExplainer(streamer: streamer, builder: ClaudeRequestBuilder(), apiKey: apiKey)
}

@Test func devuelveLaTarjetaDeUnStreamCompleto() async throws {
    let card = try await explainer(FakeStreamer(lines: sseLines(forJSON: cardJSON)))
        .explain(utterance)
    #expect(card?.english == "I need you to let me know.")
    #expect(card?.vocab.first?.term == "let me know")
}

@Test func devuelveNilCuandoElModeloMarcaSkip() async throws {
    let json = #"{"english":"","why":[],"vocab":[],"skip":true}"#
    let card = try await explainer(FakeStreamer(lines: sseLines(forJSON: json)))
        .explain(utterance)
    #expect(card == nil)
}

@Test func distingueElRateLimitDeUnErrorDeServidor() async {
    await #expect(throws: ExplainerError.rateLimited) {
        try await explainer(FakeStreamer(statusCode: 429)).explain(utterance)
    }
    await #expect(throws: ExplainerError.server(status: 503, message: "")) {
        try await explainer(FakeStreamer(statusCode: 503)).explain(utterance)
    }
}

@Test func detectaElRechazoTrasElFallback() async {
    let lines = sseLines(forJSON: cardJSON, stopReason: "refusal")
    await #expect(throws: ExplainerError.refused) {
        try await explainer(FakeStreamer(lines: lines)).explain(utterance)
    }
}

@Test func fallaLimpioSiElStreamSeCortaAMedias() async {
    let truncated = [
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"english\":\"Hi"}}"#,
    ]
    await #expect(throws: ExplainerError.malformedResponse) {
        try await explainer(FakeStreamer(lines: truncated)).explain(utterance)
    }
}

@Test func exigeApiKeyAntesDeTocarLaRed() async {
    await #expect(throws: ExplainerError.missingAPIKey) {
        try await explainer(FakeStreamer(lines: []), apiKey: "").explain(utterance)
    }
}


@Test func conservaElMensajeDeErrorDeLaAPI() async {
    // Un 400 sin mensaje es indepurable: el motivo tiene que llegar al usuario.
    let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"minItems no admitido"}}"#
    await #expect(throws: ExplainerError.server(status: 400, message: "minItems no admitido")) {
        try await explainer(FakeStreamer(statusCode: 400, lines: [body])).explain(utterance)
    }
}
