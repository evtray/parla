import Foundation

public struct ClaudeRequestBuilder: Sendable {

    public let model: String
    public let maxTokens: Int
    /// Veinte tarjetas no caben en el presupuesto de una sola.
    public let batchMaxTokens: Int

    /// Cuántas frases van en una petición de lote. Con más, la respuesta no
    /// cabe en `batchMaxTokens` y el modelo la corta a mitad de una tarjeta.
    public static let chunkSize = 20

    /// Un correo largo corregido, con su explicación y el razonamiento, no cabe
    /// en el presupuesto de una frase.
    public let captureMaxTokens: Int

    public init(model: String = "claude-opus-5-5",
                maxTokens: Int = 4000,
                batchMaxTokens: Int = 24000,
                captureMaxTokens: Int = 16000) {
        self.model = model
        self.maxTokens = maxTokens
        self.batchMaxTokens = batchMaxTokens
        self.captureMaxTokens = captureMaxTokens
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Esquemas
    //
    // Sin `minItems`/`maxItems`: la salida estructurada admite solo un
    // subconjunto de JSON Schema y los rechaza con "for 'array' type, property
    // maxItems is not supported". Los límites de longitud se imponen desde el
    // system prompt, no desde el esquema.

    /// `why` y `vocab` son iguales en la voz y en la captura: si divergieran, la
    /// UI tendría que pintar dos formas de lo mismo.
    private static var whySchema: [String: Any] {
        ["type": "array", "items": ["type": "string"]]
    }

    private static var vocabSchema: [String: Any] {
        [
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
        ]
    }

    /// Los campos de una tarjeta, compartidos por los dos esquemas para que no
    /// puedan divergir.
    private var cardProperties: [String: Any] {
        [
            "english": ["type": "string"],
            "why": Self.whySchema,
            "vocab": Self.vocabSchema,
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

    /// El esquema de una captura. Coincide con `CaptureCard`.
    private var captureSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": CaptureKind.allCases.map(\.rawValue)],
                "source": ["type": "string"],
                "result": ["type": "string"],
                "why": Self.whySchema,
                "vocab": Self.vocabSchema,
            ],
            "required": ["kind", "source", "result", "why", "vocab"],
            "additionalProperties": false,
        ]
    }

    // MARK: - Peticiones

    /// El cuerpo común. Los dos modos comparten el bloque `system` byte a byte:
    /// si difiriera, cada uno estrenaría su propia caché de prompt y el ahorro
    /// que motiva el lote se lo comería el prefijo sin cachear.
    private func payload(system: String = SystemPrompt.text,
                         content: Any,
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
                "text": system,
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
        // Claves ordenadas: un diccionario de Swift no garantiza el orden, y el
        // esquema de salida entra en el prefijo cacheado. Con el orden al azar,
        // cada petición estrenaba caché y pagaba el system prompt entero.
        request.httpBody = try JSONSerialization.data(withJSONObject: payload,
                                                      options: [.sortedKeys])
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

    /// El texto que acompaña a la imagen. Forzar `.skip` no tiene sentido y la
    /// UI no lo ofrece: si llega, decide el modelo, igual que con `nil`.
    public static func captureInstruction(forcing kind: CaptureKind?) -> String {
        switch kind {
        case .correct?:
            "El usuario indica que este texto lo escribió él. El caso es correct."
        case .understand?:
            "El usuario indica que este texto no lo escribió él y quiere entenderlo. "
                + "El caso es understand."
        case .translate?:
            "El usuario quiere saber cómo se dice este texto en inglés. El caso es translate."
        case .skip?, nil:
            "Decide tú el caso."
        }
    }

    /// La imagen va antes que el texto, que es el orden que la documentación de
    /// visión recomienda. El system prompt es el de captura y tiene su propia
    /// caché: no comparte prefijo con el de la voz.
    public func makeCaptureRequest(for capture: Capture,
                                   forcing kind: CaptureKind?,
                                   apiKey: String) throws -> URLRequest {
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": capture.mediaType,
                    "data": capture.imageData.base64EncodedString(),
                ],
            ],
            ["type": "text", "text": Self.captureInstruction(forcing: kind)],
        ]
        return try request(payload(system: CaptureSystemPrompt.text,
                                   content: content,
                                   schema: captureSchema,
                                   maxTokens: captureMaxTokens),
                           apiKey: apiKey)
    }
}
