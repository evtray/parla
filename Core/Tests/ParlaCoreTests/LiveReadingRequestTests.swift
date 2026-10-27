import Testing
import Foundation
@testable import ParlaCore

private func json(of request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func system(of request: URLRequest) throws -> String {
    let blocks = try #require(try json(of: request)["system"] as? [[String: Any]])
    return try #require(blocks.first?["text"] as? String)
}

private let context = NotebookContext(about: "RPG de fantasía; Maren es la capitana.",
                                      recentLines: ["The Gloomwood stirs again."])

@Test func elContextoLlevaDeQueTrataYLasUltimasDoce() {
    let lines = (1...15).map { "Line \($0)" }
    let context = NotebookContext(about: "Un juego", recentLines: lines)
    #expect(context.recentLines == Array(lines[3...]))
    let expected = "De qué trata: Un juego\n\nLíneas anteriores:\n"
        + (4...15).enumerated().map { "\($0.offset + 1). Line \($0.element)" }.joined(separator: "\n")
    #expect(context.promptText == expected)
}

@Test func sinDeQueTrataNoSeMandaEseBloque() {
    let context = NotebookContext(about: "  \n", recentLines: ["Hi."])
    #expect(context.promptText == "Líneas anteriores:\n1. Hi.")
    #expect(NotebookContext(about: "", recentLines: []).promptText == "")
}

@Test func laPeticionNumeraLasLineasNuevas() throws {
    let request = try ClaudeRequestBuilder(model: "claude-haiku-5-5")
        .makeLiveReadingRequest(lines: ["A", "B"], context: context, apiKey: "k")
    let content = userContent(of: request)
    #expect(content.hasPrefix(context.promptText + "\n\n"))
    #expect(content.hasSuffix("Líneas nuevas:\n1. A\n2. B"))
}

@Test func elEsquemaPideTraduccionGuardarYExpresiones() throws {
    let request = try ClaudeRequestBuilder()
        .makeLiveReadingRequest(lines: ["A"], context: context, apiKey: "k")
    let output = try #require(try json(of: request)["output_config"] as? [String: Any])
    let format = try #require(output["format"] as? [String: Any])
    let schema = try #require(format["schema"] as? [String: Any])
    #expect(schema["required"] as? [String] == ["lines"])
    let properties = try #require(schema["properties"] as? [String: Any])
    let lines = try #require(properties["lines"] as? [String: Any])
    let item = try #require(lines["items"] as? [String: Any])
    #expect(Set(item["required"] as? [String] ?? []) == ["spanish", "save", "expressions"])
    #expect(item["additionalProperties"] as? Bool == false)
    let itemProperties = try #require(item["properties"] as? [String: Any])
    let expressions = try #require(itemProperties["expressions"] as? [String: Any])
    let expression = try #require(expressions["items"] as? [String: Any])
    #expect(Set(expression["required"] as? [String] ?? []) == ["phrase", "meaning"])
    #expect(lines["maxItems"] == nil)
}

@Test func explicarComparteElSystemPromptYPideExplicar() throws {
    let builder = ClaudeRequestBuilder(model: "claude-haiku-5-5")
    let translate = try builder.makeLiveReadingRequest(lines: ["A"], context: context, apiKey: "k")
    let explain = try builder.makeExplainLineRequest(line: "A", context: context, apiKey: "k")
    #expect(try system(of: translate) == system(of: explain))
    #expect(try system(of: translate) == LiveReadingSystemPrompt.text)
    #expect(userContent(of: explain).hasSuffix(
        "Explica siempre esta línea: save en true y al menos una expresión."))
}

@Test func conHaikuLaLecturaEnVivoVaSinFallback() throws {
    let request = try ClaudeRequestBuilder(model: "claude-haiku-5-5")
        .makeLiveReadingRequest(lines: ["A"], context: context, apiKey: "k")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
    #expect(try json(of: request)["fallbacks"] == nil)
    #expect(try json(of: request)["model"] as? String == "claude-haiku-5-5")
}
