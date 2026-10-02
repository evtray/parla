import Testing
import Foundation
@testable import ParlaCore

private func body(of request: URLRequest) throws -> [String: Any] {
    // #require no se puede anidar dentro de otro #require: la macro se expande
    // recursivamente y el compilador la rechaza.
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private let utterance = Utterance(text: "necesito que me avises cuando llegues",
                                  startedAt: Date(timeIntervalSince1970: 0))

@Test func poneLasCabecerasQueLaAPIExige() throws {
    let request = try ClaudeRequestBuilder().makeRequest(for: utterance, apiKey: "sk-test")
    #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
    #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
}

@Test func pideOpus55ConEsfuerzoBajoYStreaming() throws {
    let json = try body(of: ClaudeRequestBuilder().makeRequest(for: utterance, apiKey: "k"))
    #expect(json["model"] as? String == "claude-opus-5-5")
    #expect(json["stream"] as? Bool == true)
    #expect(json["fallbacks"] as? String == "default")
    let output = try #require(json["output_config"] as? [String: Any])
    #expect(output["effort"] as? String == "low")
    // En Opus 5 el pensamiento adaptativo está activo por omisión: no se manda.
    #expect(json["thinking"] == nil)
}

@Test func fuerzaElEsquemaDeSalida() throws {
    let json = try body(of: ClaudeRequestBuilder().makeRequest(for: utterance, apiKey: "k"))
    let output = try #require(json["output_config"] as? [String: Any])
    let format = try #require(output["format"] as? [String: Any])
    #expect(format["type"] as? String == "json_schema")

    let schema = try #require(format["schema"] as? [String: Any])
    let required = try #require(schema["required"] as? [String])
    #expect(Set(required) == ["english", "why", "vocab", "skip"])
    #expect(schema["additionalProperties"] as? Bool == false)
}

@Test func cacheaElSystemPrompt() throws {
    let json = try body(of: ClaudeRequestBuilder().makeRequest(for: utterance, apiKey: "k"))
    let system = try #require(json["system"] as? [[String: Any]])
    let cache = try #require(system[0]["cache_control"] as? [String: Any])
    #expect(cache["type"] as? String == "ephemeral")
}

@Test func mandaLaFraseDelUsuarioComoMensaje() throws {
    let json = try body(of: ClaudeRequestBuilder().makeRequest(for: utterance, apiKey: "k"))
    let messages = try #require(json["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages[0]["role"] as? String == "user")
    #expect(messages[0]["content"] as? String == "necesito que me avises cuando llegues")
}

@Test func elSystemPromptEsLoBastanteLargoParaCachearse() {
    // La API no cachea prefijos por debajo de ~1024 tokens. Con ~3,5 caracteres
    // por token en español, 4000 caracteres es un margen holgado.
    #expect(SystemPrompt.text.count > 4000)
}

@Test func rechazaUnaApiKeyVacia() {
    #expect(throws: ExplainerError.missingAPIKey) {
        try ClaudeRequestBuilder().makeRequest(for: utterance, apiKey: "")
    }
}

@Test func noUsaPalabrasClaveQueLaAPIRechaza() throws {
    // La API responde 400 con "for 'array' type, property maxItems is not
    // supported": los esquemas de salida admiten solo un subconjunto de JSON
    // Schema. Los límites de longitud se imponen desde el system prompt.
    let request = try ClaudeRequestBuilder().makeRequest(for: utterance, apiKey: "k")
    let raw = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
    #expect(!raw.contains("maxItems"))
    #expect(!raw.contains("minItems"))
}

@Test func elCuerpoSaleIgualByteAByte() throws {
    // El esquema de salida entra en el prefijo cacheado: si sus claves cambian
    // de orden entre peticiones, la caché del prompt no acierta nunca.
    let builder = ClaudeRequestBuilder()
    let first = try builder.makeRequest(for: utterance, apiKey: "k").httpBody
    for _ in 0 ..< 5 {
        #expect(try builder.makeRequest(for: utterance, apiKey: "k").httpBody == first)
    }
}
