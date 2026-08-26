import Foundation

/// Decide dónde termina una frase.
///
/// Máquina de estados pura: no tiene reloj propio ni duerme. Quien la usa le
/// entrega los eventos y la hora, y llama a `tick` periódicamente.
public struct UtteranceSegmenter: Sendable {

    public struct Config: Sendable {
        /// Silencio que cierra una frase.
        public var silenceGap: TimeInterval
        /// Por encima de esto se corta sin esperar al silencio, para no dejar
        /// al usuario mirando un esqueleto durante medio minuto.
        public var maxCharacters: Int
        /// Por debajo de esto se descarta sin gastar una llamada a la API.
        public var minCharacters: Int

        public init(silenceGap: TimeInterval = 0.9,
                    maxCharacters: Int = 240,
                    minCharacters: Int = 3) {
            self.silenceGap = silenceGap
            self.maxCharacters = maxCharacters
            self.minCharacters = minCharacters
        }
    }

    private let config: Config
    private var pieces: [String] = []
    private var startedAt: Date?
    private var lastActivityAt: Date?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Entrega un evento de transcripción. Devuelve una frase si este evento la cierra.
    public mutating func ingest(_ event: TranscriptEvent, at time: Date) -> Utterance? {
        if startedAt == nil { startedAt = time }
        lastActivityAt = time

        guard case .final(let text) = event else {
            return nil   // los parciales solo mantienen viva la frase
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        pieces.append(trimmed)

        return currentText.count >= config.maxCharacters ? flush() : nil
    }

    /// Llamar periódicamente. Devuelve una frase si el silencio ya la cerró.
    public mutating func tick(at time: Date) -> Utterance? {
        guard !pieces.isEmpty, let last = lastActivityAt else { return nil }
        guard time.timeIntervalSince(last) >= config.silenceGap else { return nil }
        return flush()
    }

    private var currentText: String {
        pieces.joined(separator: " ")
    }

    private mutating func flush() -> Utterance? {
        let text = currentText
        let began = startedAt
        pieces.removeAll()
        startedAt = nil
        lastActivityAt = nil

        guard text.count >= config.minCharacters, let began else { return nil }
        return Utterance(text: text, startedAt: began)
    }
}
