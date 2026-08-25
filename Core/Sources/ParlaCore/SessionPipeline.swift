import Foundation

public enum PipelineOutput: Sendable {
    case partial(String)
    case card(Utterance, Card)
    case failure(Utterance, ExplainerError)
}

/// Une transcripción, segmentación y explicación.
///
/// Cada frase se explica en su propia `Task`: tres frases seguidas no hacen cola.
/// Por eso las tarjetas pueden llegar desordenadas y quien las muestre debe
/// ordenar por `Utterance.startedAt`.
public struct SessionPipeline: Sendable {

    private let transcriber: any Transcriber
    private let explainer: any Explainer
    private let segmenterConfig: UtteranceSegmenter.Config

    public init(transcriber: any Transcriber,
                explainer: any Explainer,
                segmenterConfig: UtteranceSegmenter.Config = .init()) {
        self.transcriber = transcriber
        self.explainer = explainer
        self.segmenterConfig = segmenterConfig
    }

    public var outputs: AsyncStream<PipelineOutput> {
        AsyncStream { continuation in
            let task = Task {
                var segmenter = UtteranceSegmenter(config: segmenterConfig)

                await withTaskGroup(of: Void.self) { group in
                    for await (event, time) in transcriber.events {
                        if case .partial(let text) = event {
                            continuation.yield(.partial(text))
                        }
                        // Un evento nuevo puede cerrar la frase anterior por silencio,
                        if let closed = segmenter.tick(at: time) {
                            explain(closed, in: &group, into: continuation)
                        }
                        // y además abre o extiende la actual.
                        if let closed = segmenter.ingest(event, at: time) {
                            explain(closed, in: &group, into: continuation)
                        }
                    }
                    // Fin del audio: cierra lo que quede pendiente.
                    if let closed = segmenter.tick(at: .distantFuture) {
                        explain(closed, in: &group, into: continuation)
                    }
                    await group.waitForAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func explain(_ utterance: Utterance,
                         in group: inout TaskGroup<Void>,
                         into continuation: AsyncStream<PipelineOutput>.Continuation) {
        let explainer = self.explainer
        group.addTask {
            do {
                if let card = try await explainer.explain(utterance) {
                    continuation.yield(.card(utterance, card))
                }
            } catch let error as ExplainerError {
                continuation.yield(.failure(utterance, error))
            } catch {
                continuation.yield(.failure(utterance, .network(error.localizedDescription)))
            }
        }
    }
}
