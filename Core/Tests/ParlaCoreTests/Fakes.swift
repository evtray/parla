import Foundation
import Testing
@testable import ParlaCore

/// Devuelve un guion fijo de líneas SSE, sin red y sin esperas.
struct FakeStreamer: HTTPStreamer {
    let statusCode: Int
    let lines: [String]
    let failWith: (any Error)?

    init(statusCode: Int = 200, lines: [String] = [], failWith: (any Error)? = nil) {
        self.statusCode = statusCode
        self.lines = lines
        self.failWith = failWith
    }

    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        if let failWith { throw failWith }
        let captured = lines
        return HTTPStreamResponse(
            statusCode: statusCode,
            lines: AsyncThrowingStream { continuation in
                for line in captured { continuation.yield(line) }
                continuation.finish()
            }
        )
    }
}

/// Explainer de mentira para probar el pipeline sin API.
struct FakeExplainer: Explainer {
    let result: Result<Card?, ExplainerError>

    func explain(_ utterance: Utterance) async throws -> Card? {
        try result.get()
    }

    func explainBatch(_ utterances: [Utterance]) async throws -> BatchOutcome {
        guard let card = try result.get() else {
            return BatchOutcome(cards: [:], summary: [], failures: [])
        }
        return BatchOutcome(cards: utterances.reduce(into: [:]) { $0[$1.id] = card },
                            summary: [],
                            failures: [])
    }
}

/// Falla si alguien lo llama. Sirve para afirmar que **no** se llama.
struct ExplodingExplainer: Explainer {
    func explain(_ utterance: Utterance) async throws -> Card? {
        Issue.record("el pipeline llamó al modelo cuando no debía")
        return nil
    }

    func explainBatch(_ utterances: [Utterance]) async throws -> BatchOutcome {
        Issue.record("el pipeline pidió un lote cuando no debía")
        return BatchOutcome(cards: [:], summary: [], failures: [])
    }
}

/// Construye las líneas SSE de una respuesta completa a partir de un JSON.
func sseLines(forJSON json: String, stopReason: String = "end_turn") -> [String] {
    // Se serializa como array de un elemento y se le quitan los corchetes: así
    // el string queda escapado exactamente como lo haría la API.
    let escaped = String(
        data: try! JSONSerialization.data(withJSONObject: [json]), encoding: .utf8
    )!.dropFirst().dropLast()

    return [
        #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":\#(escaped)}}"#,
        #"data: {"type":"content_block_stop","index":0}"#,
        #"data: {"type":"message_delta","delta":{"stop_reason":"\#(stopReason)"}}"#,
        #"data: {"type":"message_stop"}"#,
    ]
}

/// Reproduce un guion de eventos con horas fijas. No duerme: el tiempo es un dato.
struct FakeTranscriber: Transcriber {
    let script: [(TranscriptEvent, Date)]

    var events: AsyncStream<(TranscriptEvent, Date)> {
        let captured = script
        return AsyncStream { continuation in
            for item in captured { continuation.yield(item) }
            continuation.finish()
        }
    }

    func start() async throws {}
    func stop() async {}
}

/// Emite unos eventos y **deja el stream abierto**, que es lo que pasa de verdad
/// cuando dejas de hablar pero la escucha sigue encendida.
struct OpenEndedTranscriber: Transcriber {
    let script: [(TranscriptEvent, Date)]

    var events: AsyncStream<(TranscriptEvent, Date)> {
        let captured = script
        return AsyncStream { continuation in
            for item in captured { continuation.yield(item) }
            // deliberadamente sin finish(): el micrófono sigue abierto
        }
    }

    func start() async throws {}
    func stop() async {}
}

/// Responde en función de lo que se le pide, no del orden en que llega: los
/// trozos de un lote viajan en paralelo y el orden de llegada no es estable.
/// Guarda las peticiones para poder afirmar cuántas y con qué contenido.
final class ScriptedStreamer: HTTPStreamer, @unchecked Sendable {
    private let respond: @Sendable (URLRequest) -> (status: Int, lines: [String])
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { recorded } }

    init(respond: @escaping @Sendable (URLRequest) -> (status: Int, lines: [String])) {
        self.respond = respond
    }

    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        lock.withLock { recorded.append(request) }
        let (status, lines) = respond(request)
        return HTTPStreamResponse(
            statusCode: status,
            lines: AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            }
        )
    }
}

/// El texto que se le manda al modelo, extraído del cuerpo de la petición.
func userContent(of request: URLRequest) -> String {
    guard let data = request.httpBody,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let messages = root["messages"] as? [[String: Any]],
          let content = messages.first?["content"] as? String
    else { return "" }
    return content
}
