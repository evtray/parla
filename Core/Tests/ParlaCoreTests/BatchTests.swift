import Testing
import Foundation
@testable import ParlaCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func utterances(_ texts: [String]) -> [Utterance] {
    texts.enumerated().map { i, text in
        Utterance(text: text, startedAt: t0.addingTimeInterval(Double(i)))
    }
}

private func body(of request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

/// Una respuesta de lote ya serializada, como la devolvería la API.
private func batchJSON(_ entries: [(index: Int, english: String, skip: Bool)],
                       summary: [String] = []) -> String {
    let cards = entries.map { entry in
        """
        {"index":\(entry.index),"english":"\(entry.english)",\
        "why":["porque sí"],"vocab":[],"skip":\(entry.skip)}
        """
    }
    let summaryJSON = summary.map { "\"\($0)\"" }.joined(separator: ",")
    return "{\"cards\":[\(cards.joined(separator: ","))],\"summary\":[\(summaryJSON)]}"
}

// MARK: - La petición

@Test func numeraLasFrasesEnUnSoloMensaje() throws {
    let request = try ClaudeRequestBuilder()
        .makeBatchRequest(for: utterances(["hola", "qué tal", "me voy"]), apiKey: "k")
    #expect(userContent(of: request) == "1. hola\n2. qué tal\n3. me voy")
}

@Test func elLoteUsaElMismoSystemPromptQueUnaFraseSuelta() throws {
    // Byte a byte: si difiere, cada modo estrena su propia caché de prompt y
    // el ahorro que motiva el lote se lo come el prefijo sin cachear.
    let builder = ClaudeRequestBuilder()
    let single = try body(of: builder.makeRequest(for: utterances(["hola"])[0], apiKey: "k"))
    let batch = try body(of: builder.makeBatchRequest(for: utterances(["hola"]), apiKey: "k"))

    let singleSystem = try #require(single["system"] as? [[String: Any]])
    let batchSystem = try #require(batch["system"] as? [[String: Any]])
    #expect(singleSystem[0]["text"] as? String == batchSystem[0]["text"] as? String)
    #expect(batchSystem[0]["cache_control"] as? [String: Any] != nil)
}

@Test func elEsquemaDelLotePideTarjetasIndexadasYUnResumen() throws {
    let json = try body(of: ClaudeRequestBuilder()
        .makeBatchRequest(for: utterances(["hola"]), apiKey: "k"))
    let output = try #require(json["output_config"] as? [String: Any])
    let format = try #require(output["format"] as? [String: Any])
    let schema = try #require(format["schema"] as? [String: Any])

    #expect(Set(try #require(schema["required"] as? [String])) == ["cards", "summary"])

    let properties = try #require(schema["properties"] as? [String: Any])
    let cards = try #require(properties["cards"] as? [String: Any])
    let item = try #require(cards["items"] as? [String: Any])
    let required = try #require(item["required"] as? [String])
    #expect(Set(required) == ["index", "english", "why", "vocab", "skip"])
}

@Test func elLoteTampocoUsaPalabrasClaveQueLaAPIRechaza() throws {
    let request = try ClaudeRequestBuilder()
        .makeBatchRequest(for: utterances(["hola"]), apiKey: "k")
    let raw = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
    #expect(!raw.contains("maxItems"))
    #expect(!raw.contains("minItems"))
}

@Test func elLotePideSitioParaVeinteTarjetas() throws {
    let builder = ClaudeRequestBuilder()
    let single = try body(of: builder.makeRequest(for: utterances(["hola"])[0], apiKey: "k"))
    let batch = try body(of: builder.makeBatchRequest(for: utterances(["hola"]), apiKey: "k"))
    let singleMax = try #require(single["max_tokens"] as? Int)
    let batchMax = try #require(batch["max_tokens"] as? Int)
    // Veinte tarjetas no caben en el presupuesto de una sola.
    #expect(batchMax >= singleMax * 5)
}

@Test func elLoteRechazaUnaApiKeyVacia() {
    #expect(throws: ExplainerError.missingAPIKey) {
        try ClaudeRequestBuilder().makeBatchRequest(for: utterances(["hola"]), apiKey: "")
    }
}

// MARK: - El reparto de la respuesta

private func explainer(_ streamer: any HTTPStreamer, apiKey: String = "sk-test") -> ClaudeExplainer {
    ClaudeExplainer(streamer: streamer, builder: ClaudeRequestBuilder(), apiKey: apiKey)
}

private func always(_ json: String, status: Int = 200) -> ScriptedStreamer {
    ScriptedStreamer { _ in (status, sseLines(forJSON: json)) }
}

@Test func repartelasTarjetasPorIndiceYNoPorPosicion() async throws {
    // El modelo devuelve las entradas desordenadas a propósito: el índice manda.
    let batch = utterances(["uno", "dos", "tres"])
    let json = batchJSON([(3, "three", false), (1, "one", false), (2, "two", false)])
    let outcome = try await explainer(always(json)).explainBatch(batch)

    #expect(outcome.cards[batch[0].id]?.english == "one")
    #expect(outcome.cards[batch[1].id]?.english == "two")
    #expect(outcome.cards[batch[2].id]?.english == "three")
    #expect(outcome.failures.isEmpty)
}

@Test func laFraseQueElModeloOmiteSeReportaYNoSePierde() async throws {
    let batch = utterances(["uno", "dos", "tres"])
    let json = batchJSON([(1, "one", false), (3, "three", false)])
    let outcome = try await explainer(always(json)).explainBatch(batch)

    #expect(outcome.cards.count == 2)
    #expect(outcome.failures.map(\.utterance.text) == ["dos"])
    #expect(outcome.failures.first?.error == .malformedResponse)
}

@Test func laFraseMarcadaSkipNiDaTarjetaNiCuentaComoFallo() async throws {
    let batch = utterances(["eh", "hola"])
    let json = batchJSON([(1, "", true), (2, "hi", false)])
    let outcome = try await explainer(always(json)).explainBatch(batch)

    #expect(outcome.cards[batch[0].id] == nil)
    #expect(outcome.cards[batch[1].id]?.english == "hi")
    #expect(outcome.failures.isEmpty)
}

@Test func devuelveElResumenDelLote() async throws {
    let json = batchJSON([(1, "one", false)],
                         summary: ["En 3 de 7 usaste presente por present perfect."])
    let outcome = try await explainer(always(json)).explainBatch(utterances(["uno"]))
    #expect(outcome.summary == ["En 3 de 7 usaste presente por present perfect."])
}

@Test func unLoteVacioNoTocaLaRed() async throws {
    let streamer = ScriptedStreamer { _ in (200, []) }
    let outcome = try await explainer(streamer).explainBatch([])
    #expect(outcome.cards.isEmpty)
    #expect(outcome.summary.isEmpty)
    #expect(streamer.requests.isEmpty)
}

@Test func exigeLaApiKeyAntesDeMandarNingunTrozo() async {
    let streamer = ScriptedStreamer { _ in (200, []) }
    await #expect(throws: ExplainerError.missingAPIKey) {
        try await explainer(streamer, apiKey: "").explainBatch(utterances(["hola"]))
    }
    #expect(streamer.requests.isEmpty)
}

// MARK: - Troceado

@Test func parteLosLotesGrandesEnVariasPeticiones() async throws {
    let batch = utterances((1...45).map { "frase \($0)" })
    // Cada trozo se numera desde 1, así que la respuesta vale para los tres.
    let json = batchJSON((1...20).map { ($0, "english \($0)", false) })
    let streamer = always(json)
    _ = try await explainer(streamer).explainBatch(batch)

    let sizes = streamer.requests
        .map { userContent(of: $0).split(separator: "\n").count }
        .sorted()
    #expect(sizes == [5, 20, 20])
}

@Test func unTrozoQueFallaNoSeLlevaPorDelanteAlResto() async throws {
    let batch = utterances((1...25).map { "frase \($0)" })
    let json = batchJSON((1...20).map { ($0, "english \($0)", false) })
    // El trozo que contiene la frase 25 responde 500; el otro, bien.
    let streamer = ScriptedStreamer { request in
        userContent(of: request).contains("frase 25")
            ? (500, [#"{"error":{"message":"se cayó"}}"#])
            : (200, sseLines(forJSON: json))
    }
    let outcome = try await explainer(streamer).explainBatch(batch)

    #expect(outcome.cards.count == 20)
    #expect(outcome.failures.count == 5)
    #expect(outcome.failures.allSatisfy { $0.error == .server(status: 500, message: "se cayó") })
    // Las 5 que fallaron son exactamente las del trozo caído.
    #expect(Set(outcome.failures.map(\.utterance.text))
        == Set((21...25).map { "frase \($0)" }))
}

// MARK: - El pipeline en modo diferido

@Test func enModoDiferidoEmiteLaFraseSinLlamarAlModelo() async {
    let transcriber = FakeTranscriber(script: [
        (.final("hola qué tal"), t0),
        (.final("y ya está"), t0.addingTimeInterval(5.0)),
    ])
    // Si el pipeline llamase al modelo, este fake lo delataría fallando.
    let pipeline = SessionPipeline(transcriber: transcriber,
                                   explainer: ExplodingExplainer(),
                                   mode: .deferred,
                                   tickInterval: nil)

    var pending: [Utterance] = []
    var cards = 0
    for await output in pipeline.outputs {
        switch output {
        case .pending(let utterance): pending.append(utterance)
        case .card: cards += 1
        default: break
        }
    }
    pending.sort { $0.startedAt < $1.startedAt }
    #expect(pending.map(\.text) == ["hola qué tal", "y ya está"])
    #expect(cards == 0)
}
