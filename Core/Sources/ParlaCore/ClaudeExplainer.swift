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

    public func explain(_ utterance: Utterance) async throws -> Card? {
        let request = try builder.makeRequest(for: utterance, apiKey: apiKey)

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

        guard let data = json.data(using: .utf8),
              let card = try? JSONDecoder().decode(Card.self, from: data)
        else { throw ExplainerError.malformedResponse }

        return card.skip ? nil : card
    }
}
