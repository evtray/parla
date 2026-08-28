import Foundation

public struct ClaudeExplainer: Explainer {

    private let streamer: any HTTPStreamer
    private let builder: ClaudeRequestBuilder
    private let apiKey: String

    public init(streamer: any HTTPStreamer = URLSessionStreamer(),
                builder: ClaudeRequestBuilder = ClaudeRequestBuilder(),
                apiKey: String) {
        self.streamer = streamer
        self.builder = builder
        self.apiKey = apiKey
    }

    /// Extrae `error.message` del JSON de error de la API.
    private static func apiMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }

    /// Manda la petición y devuelve el JSON que el modelo fue escribiendo.
    private func streamJSON(_ request: URLRequest) async throws -> String {
        let response: HTTPStreamResponse
        do {
            response = try await streamer.stream(request)
        } catch let error as ExplainerError {
            throw error
        } catch {
            throw ExplainerError.network(error.localizedDescription)
        }

        switch response.statusCode {
        case 200:
            break
        case 429:
            throw ExplainerError.rateLimited
        default:
            // El cuerpo de un error no es SSE: es un JSON de una pieza.
            var body = ""
            for try await line in response.lines { body += line }
            throw ExplainerError.server(status: response.statusCode,
                                        message: Self.apiMessage(from: body) ?? body)
        }

        var parser = SSEParser()
        var json = ""
        var stopReason: String?

        do {
            for try await line in response.lines {
                for event in parser.consume(line: line) {
                    switch event {
                    case .textDelta(let chunk): json += chunk
                    case .messageDelta(let reason): stopReason = reason
                    case .done: break
                    }
                }
            }
        } catch {
            throw ExplainerError.network(error.localizedDescription)
        }

        if stopReason == "refusal" { throw ExplainerError.refused }
        return json
    }

    public func explain(_ utterance: Utterance) async throws -> Card? {
        let json = try await streamJSON(builder.makeRequest(for: utterance, apiKey: apiKey))

        guard let data = json.data(using: .utf8),
              let card = try? JSONDecoder().decode(Card.self, from: data)
        else { throw ExplainerError.malformedResponse }

        return card.skip ? nil : card
    }

    // MARK: - Lote

    private struct ChunkResult: Sendable {
        var cards: [Utterance.ID: Card] = [:]
        var summary: [String] = []
        var failures: [BatchFailure] = []
    }

    public func explainBatch(_ utterances: [Utterance]) async throws -> BatchOutcome {
        guard !utterances.isEmpty else {
            return BatchOutcome(cards: [:], summary: [], failures: [])
        }

        let size = ClaudeRequestBuilder.chunkSize
        let chunks = stride(from: 0, to: utterances.count, by: size).map {
            Array(utterances[$0 ..< min($0 + size, utterances.count)])
        }
        // Se construyen todas las peticiones antes de mandar ninguna: así una
        // clave ausente falla limpio y sin haber tocado la red.
        let requests = try chunks.map { try builder.makeBatchRequest(for: $0, apiKey: apiKey) }

        // Los trozos van en paralelo, pero el resumen se recompone en orden:
        // leerlo desordenado sería leer la sesión al revés.
        let results = await withTaskGroup(of: (Int, ChunkResult).self) { group in
            for (position, chunk) in chunks.enumerated() {
                group.addTask { (position, await run(requests[position], for: chunk)) }
            }
            var collected: [(Int, ChunkResult)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        var cards: [Utterance.ID: Card] = [:]
        var summary: [String] = []
        var failures: [BatchFailure] = []
        for result in results {
            cards.merge(result.cards) { current, _ in current }
            summary += result.summary
            failures += result.failures
        }
        return BatchOutcome(cards: cards, summary: summary, failures: failures)
    }

    /// Un trozo nunca lanza: lo que falla vuelve como `failures` para que el
    /// resto del lote llegue igual. Perder veinte frases porque una petición
    /// se cayó sería exactamente lo que el modo lote intenta evitar.
    private func run(_ request: URLRequest, for chunk: [Utterance]) async -> ChunkResult {
        func allFailed(_ error: ExplainerError) -> ChunkResult {
            ChunkResult(failures: chunk.map { BatchFailure(utterance: $0, error: error) })
        }

        let json: String
        do {
            json = try await streamJSON(request)
        } catch let error as ExplainerError {
            return allFailed(error)
        } catch {
            return allFailed(.network(error.localizedDescription))
        }

        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(BatchResponse.self, from: data)
        else { return allFailed(.malformedResponse) }

        var result = ChunkResult(summary: response.summary)
        var answered = Set<Int>()
        for entry in response.cards {
            // Un índice fuera de rango no es de este trozo: se ignora en vez de
            // emparejarlo con la frase equivocada.
            guard chunk.indices.contains(entry.index - 1) else { continue }
            answered.insert(entry.index)
            guard !entry.skip else { continue }
            result.cards[chunk[entry.index - 1].id] = entry.card
        }
        // Lo que el modelo no contestó no se da por perdido: se reporta.
        result.failures = chunk.enumerated()
            .filter { !answered.contains($0.offset + 1) }
            .map { BatchFailure(utterance: $0.element, error: .malformedResponse) }
        return result
    }
}
