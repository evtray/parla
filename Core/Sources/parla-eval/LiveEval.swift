import Foundation
import ParlaCore

/// Un diálogo inventado: el contexto, lo leído antes y las líneas nuevas.
private struct LiveFixture: Decodable {
    struct Line: Decodable {
        let english: String
        let expectSave: Bool
        /// Basta con que la traducción contenga una, sin mayúsculas.
        let mustMention: [String]
    }
    let about: String
    let history: [String]
    let lines: [Line]
}

/// Manda cada diálogo como una sola petición, como hace la sesión con su cola.
/// Gasta tokens: necesita PARLA_API_KEY.
func evalLive(in path: String, apiKey: String) async throws {
    let model = ProcessInfo.processInfo.environment["PARLA_MODEL"] ?? "claude-haiku-5-5"
    let folder = URL(fileURLWithPath: path)
    let files = try FileManager.default
        .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let translator = ClaudeExplainer(builder: ClaudeRequestBuilder(model: model), apiKey: apiKey)
    print("Modelo: \(model) — \(files.count) diálogos\n")

    var correct = 0
    var total = 0
    for file in files {
        let fixture = try JSONDecoder().decode(LiveFixture.self, from: Data(contentsOf: file))
        print(file.lastPathComponent)
        total += fixture.lines.count
        let results: [LiveTranslation?]
        do {
            results = try await translator.translate(
                fixture.lines.map(\.english),
                context: NotebookContext(about: fixture.about, recentLines: fixture.history))
        } catch {
            print("   ✗ \(error)\n")
            continue
        }
        for (line, result) in zip(fixture.lines, results) {
            guard let result else {
                print("   ✗ \(line.english) → sin traducir")
                continue
            }
            let saveOK = result.save == line.expectSave
            let spanish = result.spanish.lowercased()
            let mentionOK = line.mustMention.contains { spanish.contains($0.lowercased()) }
            if saveOK && mentionOK { correct += 1 }
            print("   \(saveOK && mentionOK ? "✓" : "✗") \(line.english)")
            print("      → \(result.spanish)")
            print("      save: \(result.save)\(saveOK ? "" : " (esperado \(line.expectSave))")"
                  + (mentionOK ? "" : " — no menciona \(line.mustMention)"))
            for expression in result.expressions {
                print("      • \(expression.phrase): \(expression.meaning)")
            }
        }
        print("")
    }
    print("\(correct)/\(total) líneas correctas")
}
