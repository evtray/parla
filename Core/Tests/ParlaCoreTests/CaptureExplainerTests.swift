import Testing
import Foundation
@testable import ParlaCore

private let capture = Capture(imageData: Data([1, 2, 3]),
                              mediaType: "image/png",
                              capturedAt: Date(timeIntervalSince1970: 0))

private let correctJSON = #"{"kind":"correct","source":"I am agree","#
    + #""result":"I agree.","why":["\"Agree\" ya es verbo."],"vocab":[]}"#

private func explainer(_ streamer: any HTTPStreamer, apiKey: String = "sk-test") -> ClaudeExplainer {
    ClaudeExplainer(streamer: streamer, builder: ClaudeRequestBuilder(), apiKey: apiKey)
}

/// El texto que acompaña a la imagen en la petición.
private func instruction(of request: URLRequest) -> String? {
    guard let data = request.httpBody,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let messages = root["messages"] as? [[String: Any]],
          let content = messages.first?["content"] as? [[String: Any]]
    else { return nil }
    return content.last?["text"] as? String
}

@Test func devuelveLaTarjetaDeCaptura() async throws {
    let card = try await explainer(FakeStreamer(lines: sseLines(forJSON: correctJSON)))
        .explainCapture(capture, forcing: nil)
    #expect(card.kind == .correct)
    #expect(card.result == "I agree.")
    #expect(card.why.count == 1)
}

@Test func unSkipVuelveComoTarjetaNoComoNil() async throws {
    let json = #"{"kind":"skip","source":"","result":"","why":[],"vocab":[]}"#
    let card = try await explainer(FakeStreamer(lines: sseLines(forJSON: json)))
        .explainCapture(capture, forcing: nil)
    #expect(card.kind == .skip)
}

@Test func unCasoDesconocidoEsRespuestaMalformada() async {
    let json = #"{"kind":"summarize","source":"","result":"","why":[],"vocab":[]}"#
    await #expect(throws: ExplainerError.malformedResponse) {
        try await explainer(FakeStreamer(lines: sseLines(forJSON: json)))
            .explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaDetectaElRechazo() async {
    let lines = sseLines(forJSON: correctJSON, stopReason: "refusal")
    await #expect(throws: ExplainerError.refused) {
        try await explainer(FakeStreamer(lines: lines)).explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaDistingueElRateLimit() async {
    await #expect(throws: ExplainerError.rateLimited) {
        try await explainer(FakeStreamer(statusCode: 429)).explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaFallaLimpioSiElStreamSeCorta() async {
    let truncated = [
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"kind\":\"cor"}}"#,
    ]
    await #expect(throws: ExplainerError.malformedResponse) {
        try await explainer(FakeStreamer(lines: truncated)).explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaExigeApiKeyAntesDeTocarLaRed() async {
    await #expect(throws: ExplainerError.missingAPIKey) {
        try await explainer(FakeStreamer(lines: []), apiKey: "").explainCapture(capture, forcing: nil)
    }
}

@Test func elCasoForzadoLlegaALaPeticion() async throws {
    let streamer = ScriptedStreamer { _ in (200, sseLines(forJSON: correctJSON)) }
    _ = try await explainer(streamer).explainCapture(capture, forcing: .understand)
    let request = try #require(streamer.requests.first)
    #expect(instruction(of: request)?.contains("El caso es understand.") == true)
}
