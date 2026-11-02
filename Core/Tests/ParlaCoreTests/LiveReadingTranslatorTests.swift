import Testing
import Foundation
@testable import ParlaCore

private let context = NotebookContext(about: "", recentLines: [])

private func translator(answering json: String, stopReason: String = "end_turn") -> ClaudeExplainer {
    ClaudeExplainer(streamer: FakeStreamer(lines: sseLines(forJSON: json, stopReason: stopReason)),
                    builder: ClaudeRequestBuilder(model: "claude-haiku-5-5"),
                    apiKey: "k")
}

@Test func traduceVariasLineasEnOrden() async throws {
    let result = try await translator(answering: """
        {"lines":[{"spanish":"Vamos.","save":false,"expressions":[]},
                  {"spanish":"No te preocupes.","save":true,
                   "expressions":[{"phrase":"don't sweat it","meaning":"no te preocupes"}]}]}
        """).translate(["Let's go.", "Don't sweat it."], context: context)
    #expect(result == [
        LiveTranslation(spanish: "Vamos.", save: false, expressions: []),
        LiveTranslation(spanish: "No te preocupes.", save: true,
                        expressions: [LiveExpression(phrase: "don't sweat it",
                                                     meaning: "no te preocupes")]),
    ])
}

@Test func descartaLasExpresionesVacias() async throws {
    let result = try await translator(answering: """
        {"lines":[{"spanish":"Hola.","save":true,
                   "expressions":[{"phrase":"","meaning":"x"},{"phrase":"x","meaning":"  "}]}]}
        """).translate(["Hi."], context: context)
    #expect(result.first??.expressions == [])
}

@Test func unaLineaSinEspanolQuedaSinTraducir() async throws {
    let result = try await translator(answering: """
        {"lines":[{"spanish":"","save":false,"expressions":[]},
                  {"spanish":"Gracias.","save":false,"expressions":[]}]}
        """).translate(["???", "Thanks."], context: context)
    #expect(result.count == 2)
    #expect(result[0] == nil)
    #expect(result[1]?.spanish == "Gracias.")
}

@Test func siFaltanLineasLasUltimasQuedanSinTraducir() async throws {
    let result = try await translator(answering: """
        {"lines":[{"spanish":"Uno.","save":false,"expressions":[]},
                  {"spanish":"Dos.","save":false,"expressions":[]}]}
        """).translate(["One.", "Two.", "Three."], context: context)
    #expect(result.map { $0?.spanish } == ["Uno.", "Dos.", nil])
}

@Test func unaRespuestaCortadaEsMalformada() async throws {
    let explainer = translator(answering: #"{"lines":[{"spanish":"Había una vez"#,
                               stopReason: "max_tokens")
    await #expect(throws: ExplainerError.malformedResponse) {
        _ = try await explainer.translate(["Once upon a time…"], context: context)
    }
}
