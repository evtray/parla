import CoreGraphics
import Foundation
import Observation
import ParlaCore

/// Una línea en el panel de la lectura en vivo.
struct LiveLineState: Identifiable, Equatable {
    enum Status: Equatable {
        case translating
        case translated(LiveTranslation)
        /// El motivo, para el panel.
        case untranslated(String)
    }

    let id: UUID
    let english: String
    var status: Status
    var isSaved: Bool
}

enum LiveSessionState: Equatable {
    case running
    case paused(LivePauseReason)
    case stopped
}

/// Lee el recuadro, decide qué líneas son nuevas, las traduce en orden y las
/// guarda en el cuaderno.
///
/// Hay una sola petición en vuelo: lo que llega mientras tanto espera y sale
/// en la siguiente, hasta `maxBatch` juntas. Así un diálogo pasado a toda
/// prisa no dispara una petición por línea ni las desordena.
@MainActor @Observable
final class LiveSession {
    /// 1 si Haiku no traduce bien varias líneas en una sola petición (sonda 4).
    static var maxBatch = 5

    let setup: LiveSetup
    let sessionID: UUID
    private(set) var state: LiveSessionState = .stopped
    /// La más nueva primero.
    private(set) var lines: [LiveLineState] = []
    /// «No encontré texto en el recuadro» tras un «Leer ahora» vacío.
    private(set) var notice: String?

    /// Al cambiarlo, arranca o para la lectura de fotogramas.
    var rhythm: LiveRhythm {
        didSet {
            guard rhythm != oldValue, state != .stopped else { return }
            if rhythm == .automatic { startWatching() } else { stopWatching() }
        }
    }

    @ObservationIgnored private let frames: any FrameSource
    @ObservationIgnored private let read: @Sendable (CGImage) async throws -> String
    @ObservationIgnored private let translator: any LiveReadingTranslator
    @ObservationIgnored private let store: NotebookStore
    @ObservationIgnored private var detector = LineDetector()
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private var pending: [UUID] = []
    @ObservationIgnored private var inFlight = false

    init(setup: LiveSetup, rhythm: LiveRhythm, frames: any FrameSource,
         read: @escaping @Sendable (CGImage) async throws -> String,
         translator: any LiveReadingTranslator, store: NotebookStore, sessionID: UUID = UUID()) {
        self.setup = setup
        self.rhythm = rhythm
        self.frames = frames
        self.read = read
        self.translator = translator
        self.store = store
        self.sessionID = sessionID
    }

    func start() {
        guard state == .stopped else { return }
        state = .running
        if rhythm == .automatic { startWatching() }
    }

    func stop() {
        stopWatching()
        state = .stopped
    }

    /// Lee el recuadro ya, aunque el texto sea el mismo de antes.
    func readNow() async {
        guard state != .stopped else { return }
        let text: String
        do {
            text = try await read(frames.snapshot())
        } catch {
            Log.pipeline.error("lectura en vivo: no se pudo leer el recuadro: \(error.localizedDescription)")
            notice = "No se pudo leer el recuadro"
            return
        }
        guard let line = detector.force(text) else {
            notice = "No encontré texto en el recuadro"
            return
        }
        await add(line)
    }

    func retry(_ id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }),
              case .untranslated = lines[index].status
        else { return }
        lines[index].status = .translating
        pending.append(id)
        pump()
    }

    /// Si el modelo no explicó la línea, se le pide que la explique.
    func save(_ id: UUID) {
        guard let line = lines.first(where: { $0.id == id }), !line.isSaved else { return }
        Task {
            var translation: LiveTranslation?
            if case .translated(let current) = line.status, !current.expressions.isEmpty {
                translation = current
            } else {
                let context = await store.context(notebookID: setup.notebookID, sessionID: sessionID)
                translation = try? await translator.explain(line.english, context: context)
            }
            guard let translation, let index = lines.firstIndex(where: { $0.id == id }) else {
                notice = "No se pudo guardar la línea"
                return
            }
            lines[index].status = .translated(translation)
            lines[index].isSaved = true
            await store.save(line: id, with: translation)
        }
    }

    func unsave(_ id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].isSaved = false
        Task { await store.unsave(line: id) }
    }

    // MARK: - Fotogramas

    private func startWatching() {
        stopWatching()
        let events = frames.frames()
        watching = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                await self.handle(event)
            }
        }
    }

    private func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    private func handle(_ event: LiveFrameEvent) async {
        switch event {
        case .paused(let reason):
            state = .paused(reason)
        case .resumed:
            if state != .stopped { state = .running }
        case .frame(let image):
            guard state == .running else { return }
            do {
                let text = try await read(image)
                if let line = detector.feed(text) { await add(line) }
            } catch {
                Log.pipeline.error("lectura en vivo: Vision falló: \(error.localizedDescription)")
                state = .paused(.readerFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Cola

    private func add(_ english: String) async {
        // Con la fuente «pantalla», el recuadro puede incluir la traducción de
        // Parla: leerla otra vez la traduciría en bucle.
        let ownTranslations = lines.prefix(NotebookContext.lineLimit).compactMap { line in
            if case .translated(let translation) = line.status {
                LineDetector.normalize(translation.spanish)
            } else { nil }
        }
        guard !ownTranslations.contains(english) else { return }

        notice = nil
        let id = UUID()
        lines.insert(LiveLineState(id: id, english: english, status: .translating, isSaved: false),
                     at: 0)
        await store.insertLine(id: id, english: english, sessionID: sessionID,
                               notebookID: setup.notebookID, readAt: Date())
        pending.append(id)
        pump()
    }

    private func pump() {
        guard !inFlight, !pending.isEmpty else { return }
        let batch = Array(pending.prefix(Self.maxBatch))
        pending.removeFirst(batch.count)
        let english = batch.map { id in lines.first { $0.id == id }?.english ?? "" }
        inFlight = true
        Task {
            let context = await store.context(notebookID: setup.notebookID, sessionID: sessionID)
            do {
                let results = try await translator.translate(english, context: context)
                for (id, result) in zip(batch, results) {
                    update(id, to: result.map { .translated($0) } ?? .untranslated("No se pudo traducir"),
                           saved: result?.save ?? false)
                    await store.apply(result, toLine: id)
                }
            } catch {
                let message = Self.message(for: error)
                for id in batch { update(id, to: .untranslated(message), saved: false) }
            }
            inFlight = false
            pump()
        }
    }

    private func update(_ id: UUID, to status: LiveLineState.Status, saved: Bool) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].status = status
        lines[index].isSaved = saved
    }

    static func message(for error: any Error) -> String {
        switch error as? ExplainerError {
        case .missingAPIKey?: "Falta la clave de API"
        case .rateLimited?: "Demasiadas peticiones; prueba en un momento"
        case .network?: "Sin conexión"
        default: "No se pudo traducir"
        }
    }
}
