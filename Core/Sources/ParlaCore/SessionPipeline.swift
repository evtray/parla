import Foundation

public enum PipelineOutput: Sendable {
    case partial(String)
    case card(Utterance, Card)
    case failure(Utterance, ExplainerError)
    /// Frase cerrada y sin explicar, en modo diferido. La explicación la pide
    /// quien consume, cuando quiera.
    case pending(Utterance)
}

/// Une transcripción, segmentación y explicación.
///
/// Cada frase se explica en su propia `Task`: tres frases seguidas no hacen cola.
/// Por eso las tarjetas pueden llegar desordenadas y quien las muestre debe
/// ordenar por `Utterance.startedAt`.
public struct SessionPipeline: Sendable {

    public enum Mode: Sendable, Equatable {
        /// Una petición por frase, en cuanto se cierra.
        case immediate
        /// No se llama al modelo: cada frase cerrada sale por `.pending` y se
        /// acumula hasta que alguien pide el lote.
        case deferred
    }

    /// Lo que consume el bucle: eventos del transcriptor y latidos del reloj,
    /// fundidos en una sola secuencia para que el segmentador siga siendo un
    /// struct manipulado desde un único sitio.
    private enum Beat: Sendable {
        case event(TranscriptEvent, Date)
        case tick(Date)
    }

    private let transcriber: any Transcriber
    private let explainer: any Explainer
    private let mode: Mode
    private let segmenterConfig: UtteranceSegmenter.Config
    /// Cada cuánto se comprueba el silencio. `nil` desactiva el reloj: los tests
    /// que usan horas fijas lo apagan para no mezclar tiempo real con simulado.
    private let tickInterval: Duration?

    public init(transcriber: any Transcriber,
                explainer: any Explainer,
                mode: Mode = .immediate,
                segmenterConfig: UtteranceSegmenter.Config = .init(),
                tickInterval: Duration? = .milliseconds(200)) {
        self.transcriber = transcriber
        self.explainer = explainer
        self.mode = mode
        self.segmenterConfig = segmenterConfig
        self.tickInterval = tickInterval
    }

    public var outputs: AsyncStream<PipelineOutput> {
        AsyncStream { continuation in
            let task = Task {
                var segmenter = UtteranceSegmenter(config: segmenterConfig)
                let (beats, feed) = AsyncStream<Beat>.makeStream()

                let forwarding = Task {
                    for await (event, time) in transcriber.events {
                        feed.yield(.event(event, time))
                    }
                    feed.finish()
                }

                // Sin este reloj, una frase seguida de silencio no se cierra
                // nunca: el silencio se detecta comparando horas, y sin eventos
                // nadie hace la comparación.
                let ticking = Task {
                    guard let interval = tickInterval else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: interval)
                        feed.yield(.tick(Date()))
                    }
                }

                await withTaskGroup(of: Void.self) { group in
                    for await beat in beats {
                        switch beat {
                        case .tick(let time):
                            if let closed = segmenter.tick(at: time) {
                                close(closed, in: &group, into: continuation)
                            }
                        case .event(let event, let time):
                            if case .partial(let text) = event {
                                continuation.yield(.partial(text))
                            }
                            // Un evento nuevo puede cerrar la frase anterior por silencio,
                            if let closed = segmenter.tick(at: time) {
                                close(closed, in: &group, into: continuation)
                            }
                            // y además abre o extiende la actual.
                            if let closed = segmenter.ingest(event, at: time) {
                                close(closed, in: &group, into: continuation)
                            }
                        }
                    }
                    // Fin del audio: cierra lo que quede pendiente.
                    if let closed = segmenter.tick(at: .distantFuture) {
                        close(closed, in: &group, into: continuation)
                    }
                    await group.waitForAll()
                }
                forwarding.cancel()
                ticking.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func close(_ utterance: Utterance,
                       in group: inout TaskGroup<Void>,
                       into continuation: AsyncStream<PipelineOutput>.Continuation) {
        guard mode == .immediate else {
            continuation.yield(.pending(utterance))
            return
        }
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
