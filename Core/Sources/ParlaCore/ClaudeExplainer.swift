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
        case 200: break
        case 429: throw ExplainerError.rateLimited
        default: throw ExplainerError.server(status: response.statusCode)
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
