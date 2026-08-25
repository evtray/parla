import Foundation

public struct ClaudeRequestBuilder: Sendable {

    public let model: String
    public let maxTokens: Int

    public init(model: String = "claude-opus-5", maxTokens: Int = 4000) {
        self.model = model
        self.maxTokens = maxTokens
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// El esquema que la API fuerza sobre la respuesta. Coincide con `Card`.
    private var outputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "english": ["type": "string"],
                "why": ["type": "array", "items": ["type": "string"],
                        "minItems": 1, "maxItems": 3],
                "vocab": [
                    "type": "array", "maxItems": 3,
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
            ],
            "required": ["english", "why", "vocab", "skip"],
            "additionalProperties": false,
        ]
    }

    public func makeRequest(for utterance: Utterance, apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw ExplainerError.missingAPIKey }

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            // Si un clasificador declina la frase, la API reintenta sola.
            "fallbacks": "default",
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": outputSchema],
            ],
            "system": [[
                "type": "text",
                "text": SystemPrompt.text,
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [["role": "user", "content": utterance.text]],
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }
}
