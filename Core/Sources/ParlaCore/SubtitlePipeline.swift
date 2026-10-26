import Foundation

/// Une la transcripción con la traducción y emite lo que la banda tiene que
/// mostrar. Las decisiones son de `SubtitleState`; aquí solo se ejecutan.
public struct SubtitlePipeline: Sendable {

    private enum Beat: Sendable {
        case event(TranscriptEvent, Date)
        case tick(Date)
        case translated(SubtitleState.Request, String?)
        /// El transcriptor terminó: se espera a las traducciones en vuelo.
        case ended
    }

    private let transcriber: any Transcriber
    private let translator: any Translator
    private let config: SubtitleState.Config
    /// Cada cuánto se comprueban el intervalo de los parciales y el silencio.
    /// `nil` lo apaga, para los tests con horas fijas.
    private let tickInterval: Duration?

    public init(transcriber: any Transcriber,
                translator: any Translator,
                config: SubtitleState.Config = .init(),
                tickInterval: Duration? = .milliseconds(50)) {
        self.transcriber = transcriber
        self.translator = translator
        self.config = config
        self.tickInterval = tickInterval
    }

    public var outputs: AsyncStream<SubtitleOutput> {
        AsyncStream { continuation in
            let task = Task {
                var state = SubtitleState(config: config)
                let (beats, feed) = AsyncStream<Beat>.makeStream()
                let translator = self.translator

                let forwarding = Task {
                    for await (event, time) in transcriber.events {
                        feed.yield(.event(event, time))
                    }
                    feed.yield(.ended)
                }
                let ticking = Task {
                    guard let interval = tickInterval else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: interval)
                        feed.yield(.tick(Date()))
                    }
                }

                var inFlight = 0
                var ended = false
                func run(_ actions: [SubtitleState.Action]) {
                    for action in actions {
                        switch action {
                        case .output(let output):
                            continuation.yield(output)
                        case .translate(let request):
                            inFlight += 1
                            Task {
                                let text = try? await translator.translate(request.text)
                                feed.yield(.translated(request, text))
                            }
                        }
                    }
                }

                for await beat in beats {
                    switch beat {
                    case .event(let event, let time):
                        run(state.ingest(event, at: time))
                    case .tick(let time):
                        run(state.tick(at: time))
                    case .translated(let request, let text):
                        inFlight -= 1
                        run(state.receive(request, translation: text))
                    case .ended:
                        ended = true
                    }
                    if ended && inFlight == 0 { break }
                }
                forwarding.cancel()
                ticking.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
