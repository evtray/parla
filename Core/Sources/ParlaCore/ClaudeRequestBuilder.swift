import Foundation

public struct ClaudeRequestBuilder: Sendable {

    public let model: String
    public let maxTokens: Int
    /// Veinte tarjetas no caben en el presupuesto de una sola.
    public let batchMaxTokens: Int

    /// Cuántas frases van en una petición de lote. Con más, la respuesta no
    /// cabe en `batchMaxTokens` y el modelo la corta a mitad de una tarjeta.
    public static let chunkSize = 20

    public init(model: String = "claude-opus-5",
                maxTokens: Int = 4000,
                batchMaxTokens: Int = 24000) {
        self.model = model
        self.maxTokens = maxTokens
        self.batchMaxTokens = batchMaxTokens
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Esquemas
    //
    // Sin `minItems`/`maxItems`: la salida estructurada admite solo un
    // subconjunto de JSON Schema y los rechaza con "for 'array' type, property
    // maxItems is not supported". Los límites de longitud se imponen desde el
    // system prompt, no desde el esquema.

    /// Los campos de una tarjeta, compartidos por los dos esquemas para que no
    /// puedan divergir.
    private var cardProperties: [String: Any] {
        [
            "english": ["type": "string"],
            "why": ["type": "array", "items": ["type": "string"]],
            "vocab": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "term": ["type": "string"],
                        "meaning": ["type": "string"],
                    ],
                    "required": ["term", "meaning"],
                    "additionalProperties": false,
                ],
            ],
            "skip": ["type": "boolean"],
        ]
    }

    private static let cardFields = ["english", "why", "vocab", "skip"]

    /// El esquema de una frase suelta. Coincide con `Card`.
    private var outputSchema: [String: Any] {
        [
            "type": "object",
            "properties": cardProperties,
            "required": Self.cardFields,
            "additionalProperties": false,
        ]
    }

    /// El esquema del lote. Coincide con `BatchResponse`.
    private var batchSchema: [String: Any] {
        var entry = cardProperties
        entry["index"] = ["type": "integer"]
        return [
            "type": "object",
            "properties": [
                "cards": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": entry,
                        "required": ["index"] + Self.cardFields,
                        "additionalProperties": false,
                    ],
                ],
                "summary": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["cards", "summary"],
            "additionalProperties": false,
        ]
    }

    // MARK: - Peticiones

    /// El cuerpo común. Los dos modos comparten el bloque `system` byte a byte:
    /// si difiriera, cada uno estrenaría su propia caché de prompt y el ahorro
    /// que motiva el lote se lo comería el prefijo sin cachear.
    private func payload(content: String,
                         schema: [String: Any],
                         maxTokens: Int) -> [String: Any] {
        [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            // Si un clasificador declina la frase, la API reintenta sola.
            "fallbacks": "default",
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "system": [[
                "type": "text",
                "text": SystemPrompt.text,
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [["role": "user", "content": content]],
        ]
    }

    private func request(_ payload: [String: Any], apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw ExplainerError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    public func makeRequest(for utterance: Utterance, apiKey: String) throws -> URLRequest {
        try request(payload(content: utterance.text,
                            schema: outputSchema,
                            maxTokens: maxTokens),
                    apiKey: apiKey)
    }

    /// Numera desde 1 en cada trozo: el modelo responde con esos mismos números
    /// y quien reparte las tarjetas solo mira dentro de su trozo.
    public func makeBatchRequest(for utterances: [Utterance],
                                 apiKey: String) throws -> URLRequest {
        let numbered = utterances.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")
        return try request(payload(content: numbered,
                                   schema: batchSchema,
                                   maxTokens: batchMaxTokens),
                           apiKey: apiKey)
    }
}
