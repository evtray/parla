import Testing
import Foundation
@testable import ParlaCore

private func body(of request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private func content(of json: [String: Any]) throws -> [[String: Any]] {
    let messages = try #require(json["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    return try #require(messages.first?["content"] as? [[String: Any]])
}

/// Los cuatro primeros bytes de un PNG: "iVBORw==" en base64.
private let capture = Capture(imageData: Data([0x89, 0x50, 0x4E, 0x47]),
                              mediaType: "image/png",
                              capturedAt: Date(timeIntervalSince1970: 0))

private func captureRequest(forcing kind: CaptureKind? = nil) throws -> URLRequest {
    try ClaudeRequestBuilder().makeCaptureRequest(for: capture, forcing: kind, apiKey: "k")
}

@Test func laImagenVaPrimeroYEnBase64() throws {
    let blocks = try content(of: body(of: captureRequest()))
    #expect(blocks.count == 2)
    #expect(blocks[0]["type"] as? String == "image")
    let source = try #require(blocks[0]["source"] as? [String: Any])
    #expect(source["type"] as? String == "base64")
    #expect(source["media_type"] as? String == "image/png")
    #expect(source["data"] as? String == "iVBORw==")
    #expect(blocks[1]["type"] as? String == "text")
}

@Test func sinForzarDejaQueDecidaElModelo() throws {
    let blocks = try content(of: body(of: captureRequest()))
    #expect(blocks[1]["text"] as? String == "Decide tú el caso.")
}

@Test func forzarUnCasoLoDiceEnElTexto() throws {
    let blocks = try content(of: body(of: captureRequest(forcing: .correct)))
    let text = try #require(blocks[1]["text"] as? String)
    #expect(text.contains("El caso es correct."))
}

@Test func forzarSkipEsComoNoForzar() {
    #expect(ClaudeRequestBuilder.captureInstruction(forcing: .skip)
            == ClaudeRequestBuilder.captureInstruction(forcing: nil))
}

@Test func usaElPromptDeCapturaCacheado() throws {
    let system = try #require(body(of: captureRequest())["system"] as? [[String: Any]])
    #expect(system[0]["text"] as? String == CaptureSystemPrompt.text)
    let cache = try #require(system[0]["cache_control"] as? [String: Any])
    #expect(cache["type"] as? String == "ephemeral")
}

@Test func elEsquemaDeCapturaTieneLosCuatroCasos() throws {
    let json = try body(of: captureRequest())
    let output = try #require(json["output_config"] as? [String: Any])
    let format = try #require(output["format"] as? [String: Any])
    let schema = try #require(format["schema"] as? [String: Any])
    let required = try #require(schema["required"] as? [String])
    #expect(Set(required) == ["kind", "source", "target", "why", "vocab"])
    #expect(schema["additionalProperties"] as? Bool == false)
    let properties = try #require(schema["properties"] as? [String: Any])
    let kind = try #require(properties["kind"] as? [String: Any])
    #expect(kind["enum"] as? [String] == ["understand", "correct", "translate", "skip"])
}

@Test func laCapturaTieneMasPresupuestoYElMismoEsfuerzo() throws {
    let request = try captureRequest()
    let json = try body(of: request)
    #expect(json["max_tokens"] as? Int == 16000)
    #expect(json["model"] as? String == "claude-opus-5-5")
    #expect(json["stream"] as? Bool == true)
    #expect(json["fallbacks"] as? String == "default")
    let output = try #require(json["output_config"] as? [String: Any])
    #expect(output["effort"] as? String == "low")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
}

@Test func laCapturaNoUsaPalabrasClaveQueLaAPIRechaza() throws {
    let raw = String(data: try #require(captureRequest().httpBody), encoding: .utf8) ?? ""
    #expect(!raw.contains("maxItems"))
    #expect(!raw.contains("minItems"))
}

@Test func laCapturaExigeApiKey() {
    #expect(throws: ExplainerError.missingAPIKey) {
        try ClaudeRequestBuilder().makeCaptureRequest(for: capture, forcing: nil, apiKey: "")
    }
}

@Test func laCapturaSaleIgualByteAByte() throws {
    let first = try captureRequest().httpBody
    for _ in 0 ..< 5 {
        #expect(try captureRequest().httpBody == first)
    }
}

@Test func elEsquemaPideLeerAntesDeResponder() throws {
    // El modelo escribe los campos en el orden del esquema, y el cuerpo sale
    // con las claves ordenadas. Si la respuesta va antes que el texto leído,
    // la escribe sin haber transcrito nada y a veces la deja vacía.
    let raw = String(data: try #require(captureRequest().httpBody), encoding: .utf8) ?? ""
    let properties = try #require(raw.range(of: #""properties":{"#))
    let tail = raw[properties.upperBound...]
    let order = ["\"kind\":", "\"source\":", "\"target\":", "\"vocab\":", "\"why\":"]
        .map { tail.range(of: $0)?.lowerBound }
    #expect(order.allSatisfy { $0 != nil })
    #expect(order.compactMap { $0 } == order.compactMap { $0 }.sorted())
}

@Test func laRespuestaViajaComoTarget() throws {
    let json = #"{"kind":"correct","source":"I am agree","target":"I agree.","why":[],"vocab":[]}"#
    let card = try JSONDecoder().decode(CaptureCard.self, from: Data(json.utf8))
    #expect(card.result == "I agree.")
}
