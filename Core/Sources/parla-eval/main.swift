import Foundation
import ParlaCore

// Uso: PARLA_API_KEY=… swift run parla-eval <carpeta>
// El caso esperado va al principio del nombre: correct-03-borrador.png.
// PARLA_MODEL cambia el modelo (por defecto, el de la app).

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

let explainer = ClaudeExplainer(builder: ClaudeRequestBuilder(model: model), apiKey: apiKey)
print("Modelo: \(model) — \(files.count) capturas\n")

var hits = 0
for file in files {
    let name = file.lastPathComponent
    let expected = name.split(separator: "-").first.flatMap { CaptureKind(rawValue: String($0)) }
    let mediaType = file.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
    let capture = Capture(imageData: try Data(contentsOf: file),
                          mediaType: mediaType,
                          capturedAt: Date())
    do {
        let card = try await explainer.explainCapture(capture, forcing: nil)
        let ok = card.kind == expected
        if ok { hits += 1 }
        print("\(ok ? "✓" : "✗") \(name): esperado \(expected?.rawValue ?? "?"), "
              + "eligió \(card.kind.rawValue)")
        print("   source: \(card.source)")
        print("   result: \(card.result)")
        for line in card.why { print("   • \(line)") }
        if !card.vocab.isEmpty {
            print("   vocab: " + card.vocab.map { "\($0.term) = \($0.meaning)" }
                .joined(separator: " | "))
        }
    } catch {
        print("✗ \(name): \(error)")
    }
    print("")
}
print("Acierto: \(hits)/\(files.count)")
