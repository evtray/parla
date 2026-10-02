import Foundation
import ParlaCore

// Uso: PARLA_API_KEY=… swift run parla-eval <carpeta>
// El caso esperado va al principio del nombre: correct-03-borrador.png.
// PARLA_MODEL cambia el modelo (por defecto, el de la app).

/// Guarda las líneas SSE de la última petición. Cuando una tarjeta falla, el
/// stream crudo es lo único que dice por qué: un `error` a mitad de camino, un
/// bloque `fallback`, un JSON cortado.
final class RecordingStreamer: HTTPStreamer, @unchecked Sendable {
    private let inner = URLSessionStreamer()
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] { lock.withLock { recorded } }

    func reset() { lock.withLock { recorded = [] } }

    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        let response = try await inner.stream(request)
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in response.lines {
                        self.lock.withLock { self.recorded.append(line) }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return HTTPStreamResponse(statusCode: response.statusCode, lines: lines)
    }

    /// Los tokens leídos de la caché, según `message_start`.
    var cacheReadTokens: Int? {
        for line in lines where line.hasPrefix("data:") && line.contains("message_start") {
            guard let data = line.dropFirst("data:".count).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = root["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }
            return usage["cache_read_input_tokens"] as? Int
        }
        return nil
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("uso: parla-eval <carpeta con capturas>")
    exit(2)
}
guard let apiKey = ProcessInfo.processInfo.environment["PARLA_API_KEY"], !apiKey.isEmpty else {
    print("Falta PARLA_API_KEY.")
    exit(2)
}
let model = ProcessInfo.processInfo.environment["PARLA_MODEL"] ?? "claude-opus-5-5"

let folder = URL(fileURLWithPath: arguments[1])
let files = try FileManager.default
    .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

// Los streams de las capturas que fallan, para leerlos después.
let failures = FileManager.default.temporaryDirectory.appending(path: "parla-eval")
try FileManager.default.createDirectory(at: failures, withIntermediateDirectories: true)

let streamer = RecordingStreamer()
let explainer = ClaudeExplainer(streamer: streamer,
                                builder: ClaudeRequestBuilder(model: model),
                                apiKey: apiKey)
print("Modelo: \(model) — \(files.count) capturas\n")

/// Guarda el stream crudo y devuelve dónde quedó.
func saveStream(of name: String) -> String {
    let file = failures.appending(path: "\(name).sse")
    try? streamer.lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    return file.path
}

var hits = 0
var apiErrors = 0
for file in files {
    let name = file.lastPathComponent
    let expected = name.split(separator: "-").first.flatMap { CaptureKind(rawValue: String($0)) }
    let mediaType = file.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
    let capture = Capture(imageData: try Data(contentsOf: file),
                          mediaType: mediaType,
                          capturedAt: Date())
    streamer.reset()
    do {
        let card = try await explainer.explainCapture(capture, forcing: nil)
        // Elegir bien el caso no basta: fuera de skip, una tarjeta sin
        // resultado no le sirve a nadie.
        let emptyResult = card.kind != .skip && card.result.isEmpty
        let ok = card.kind == expected && !emptyResult
        if ok { hits += 1 }
        print("\(ok ? "✓" : "✗") \(name): esperado \(expected?.rawValue ?? "?"), "
              + "eligió \(card.kind.rawValue)\(emptyResult ? " — result vacío" : "")")
        print("   source: \(card.source)")
        print("   result: \(card.result)")
        for line in card.why { print("   • \(line)") }
        if !card.vocab.isEmpty {
            print("   vocab: " + card.vocab.map { "\($0.term) = \($0.meaning)" }
                .joined(separator: " | "))
        }
        print("   caché leída: \(streamer.cacheReadTokens.map(String.init) ?? "?") tokens")
        if !ok { print("   stream: \(saveStream(of: name))") }
    } catch {
        apiErrors += 1
        print("✗ \(name): \(error)")
        print("   stream: \(saveStream(of: name))")
    }
    print("")
}
print("Acierto: \(hits)/\(files.count)"
      + (apiErrors > 0 ? " — \(apiErrors) sin respuesta válida de la API" : ""))
