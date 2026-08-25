import Foundation
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
