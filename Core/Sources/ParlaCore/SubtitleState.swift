import Foundation

/// Decide qué se traduce y qué se ve en la banda.
///
/// Pura, como `UtteranceSegmenter`: no tiene reloj ni traduce. Quien la usa le
/// entrega eventos, latidos y traducciones, y ejecuta las acciones que devuelve.
public struct SubtitleState: Sendable {

    public struct Config: Sendable {
        /// Como mucho una traducción de parcial cada tanto: más rápido no se
        /// lee y hace parpadear el texto.
        public var partialInterval: TimeInterval
        /// Silencio tras el que la banda se oculta.
        public var silenceTimeout: TimeInterval

        public init(partialInterval: TimeInterval = 0.25, silenceTimeout: TimeInterval = 4) {
            self.partialInterval = partialInterval
            self.silenceTimeout = silenceTimeout
        }
    }

    /// Una traducción pedida. `id` crece con cada petición y ordena las
    /// respuestas, que llegan desordenadas; `line` dice de qué frase es.
    public struct Request: Sendable, Equatable {
        public let id: Int
        public let line: Int
        public let text: String
        public let isFinal: Bool

        public init(id: Int, line: Int, text: String, isFinal: Bool) {
            self.id = id
            self.line = line
            self.text = text
            self.isFinal = isFinal
        }
    }

    public enum Action: Sendable, Equatable {
        case translate(Request)
        case output(SubtitleOutput)
    }

    private struct Shown {
        var text: String
        var isFinal: Bool
        var isOriginal: Bool
    }

    private let config: Config
    private var nextID = 0
    /// La frase que se está diciendo.
    private var line = 0
    /// La frase actual ya recibió su final: el próximo evento abre otra.
    private var lineClosed = false
    private var lineStartedAt: Date?
    private var lastActivityAt: Date?
    private var lastPartialRequestAt: Date?
    /// El último parcial, esperando a que pase el intervalo.
    private var waitingPartial: String?
    /// La respuesta más nueva mostrada para la frase actual.
    private var shownID = -1
    private var current: Shown?
    private var previous: String?
    /// Finales pedidos y aún sin respuesta: se guardan una sola vez.
    private var pendingFinals: [Int: (english: String, startedAt: Date)] = [:]
    private var visible = false

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func ingest(_ event: TranscriptEvent, at time: Date) -> [Action] {
        switch event {
        case .partial(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            openLineIfNeeded(at: time)
            lastActivityAt = time
            waitingPartial = trimmed
            return flushPartial(at: time)

        case .final(let text):
            // El motor emite un final vacío al cerrarse el stream: no es una frase.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            openLineIfNeeded(at: time)
            lastActivityAt = time
            waitingPartial = nil
            let request = makeRequest(trimmed, isFinal: true)
            pendingFinals[request.id] = (trimmed, lineStartedAt ?? time)
            lineClosed = true
            return [.translate(request)]
        }
    }

    public mutating func tick(at time: Date) -> [Action] {
        var actions = flushPartial(at: time)
        if visible, let last = lastActivityAt,
           time.timeIntervalSince(last) >= config.silenceTimeout {
            visible = false
            // Tras una pausa, lo de antes no vuelve a aparecer arriba.
            previous = nil
            if lineClosed { current = nil }
            actions.append(.output(.hide))
        }
        return actions
    }

    /// `translation == nil` si la traducción falló.
    public mutating func receive(_ request: Request, translation: String?) -> [Action] {
        var actions: [Action] = []
        if request.isFinal, let final = pendingFinals.removeValue(forKey: request.id) {
            actions.append(.output(.line(SubtitleLine(
                english: final.english, spanish: translation ?? "", spokenAt: final.startedAt))))
        }

        let shown = Shown(text: translation ?? request.text,
                          isFinal: request.isFinal,
                          isOriginal: translation == nil)
        if request.line == line {
            // Una respuesta vieja no pisa a una más nueva de la misma frase.
            guard request.id > shownID else { return actions }
            shownID = request.id
            current = shown
        } else if request.line == line - 1, request.isFinal {
            // El final de la frase anterior llegó cuando ya empezó otra.
            previous = shown.text
            guard current != nil else { return actions }
        } else {
            return actions
        }

        guard let current else { return actions }
        visible = true
        actions.append(.output(.show(SubtitleFrame(
            previous: previous, current: current.text,
            currentIsFinal: current.isFinal, currentIsOriginal: current.isOriginal))))
        return actions
    }

    private mutating func openLineIfNeeded(at time: Date) {
        guard lineClosed else {
            if lineStartedAt == nil { lineStartedAt = time }
            return
        }
        // La frase anterior sube con lo último que se vio de ella.
        previous = current?.text ?? previous
        current = nil
        shownID = -1
        line += 1
        lineClosed = false
        lineStartedAt = time
        // El primer parcial de una frase nueva no espera al intervalo.
        lastPartialRequestAt = nil
    }

    private mutating func flushPartial(at time: Date) -> [Action] {
        guard let text = waitingPartial else { return [] }
        if let last = lastPartialRequestAt,
           time.timeIntervalSince(last) < config.partialInterval { return [] }
        waitingPartial = nil
        lastPartialRequestAt = time
        return [.translate(makeRequest(text, isFinal: false))]
    }

    private mutating func makeRequest(_ text: String, isFinal: Bool) -> Request {
        defer { nextID += 1 }
        return Request(id: nextID, line: line, text: text, isFinal: isFinal)
    }
}
