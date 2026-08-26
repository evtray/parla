import Foundation

public enum SSEEvent: Sendable, Equatable {
    case textDelta(String)
    case messageDelta(stopReason: String?)
    case done
}

/// Traduce el stream SSE de la API de Messages a eventos útiles.
///
/// Lleva la cuenta de qué índices de bloque son de tipo `text`, para descartar
/// los deltas de los bloques `thinking`, que en Opus 5 llegan antes.
public struct SSEParser: Sendable {

    private var textBlockIndices: Set<Int> = []

    public init() {}

    public mutating func consume(line: String) -> [SSEEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String
        else { return [] }

        switch type {
        case "content_block_start":
            if let index = root["index"] as? Int,
               let block = root["content_block"] as? [String: Any],
               block["type"] as? String == "text" {
                textBlockIndices.insert(index)
            }
            return []

        case "content_block_delta":
            guard let index = root["index"] as? Int,
                  textBlockIndices.contains(index),
                  let delta = root["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return [] }
            return [.textDelta(text)]

        case "message_delta":
            let delta = root["delta"] as? [String: Any]
            return [.messageDelta(stopReason: delta?["stop_reason"] as? String)]

        case "message_stop":
            return [.done]

        default:
            return []
        }
    }
}
