import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import ParlaCore

@MainActor
@Observable
final class AppState {

    private(set) var isListening = false
    private(set) var partialText = ""
    private(set) var setupError: String?
    private(set) var downloadProgress: Double?
    /// Mensaje visible cuando el dispositivo de entrada no entrega audio.
    private(set) var silentInputWarning: String?
    private(set) var cards: [CardPresentation] = []

    private(set) var captureError: String?
    private(set) var isSubtitling = false
    @ObservationIgnored let subtitleModel = SubtitleModel()
    @ObservationIgnored private var subtitleOverlay: SubtitleOverlay?
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleEngine: SpeechTranscriberEngine?
    @ObservationIgnored private var subtitleSpeaker: SubtitleSpeaker?

    /// Se persiste al cambiarlo. Apagarla calla lo que esté sonando.
    var readsSubtitlesAloud: Bool = Preferences.shared.readsSubtitlesAloud {
        didSet {
            Preferences.shared.readsSubtitlesAloud = readsSubtitlesAloud
            if !readsSubtitlesAloud { subtitleSpeaker?.stop() }
        }
    }

    /// Se persiste al cambiarlo: el modo sobrevive a cerrar la app.
    var mode: TranslationMode = Preferences.shared.translationMode {
        didSet { Preferences.shared.translationMode = mode }
    }

    /// Vale para la siguiente escucha, lote o reintento: una sesión en marcha
    /// no cambia de modelo a mitad.
    var model: ClaudeModel = Preferences.shared.model {
        didSet { Preferences.shared.model = model }
    }

    /// `nil` es el micrófono del sistema. Como el modelo, vale para la
    /// siguiente escucha.
    var inputDeviceUID: String? = Preferences.shared.inputDeviceUID {
        didSet { Preferences.shared.inputDeviceUID = inputDeviceUID }
    }

    let audioDevices = AudioDeviceMonitor()

    /// Qué falta por preparar. Lo leen la bienvenida, el menú emergente,
    /// Estudio y el panel.
    let setup = SetupMonitor(sources: LiveSetupSources())

    /// El modo que se intentó arrancar sin tener lo que necesita. El panel y el
    /// menú emergente enseñan primero sus pendientes.
    private(set) var blockedMode: ParlaMode?

    /// Los pendientes del modo bloqueado, con su arreglo.
    var panelIssues: [SetupIssue] {
        blockedMode.map { setup.status.blockers(for: $0) } ?? []
    }

    /// Los errores de esta sesión, en el orden en que se enseñan.
    var runtimeNotices: [RuntimeNotice] {
        [setupError.map(RuntimeNotice.setup),
         captureError.map(RuntimeNotice.capture),
         silentInputWarning.map(RuntimeNotice.silentInput),
         batchError.map(RuntimeNotice.batch)]
            .compactMap { $0 }
    }

    func dismiss(_ notice: RuntimeNotice) {
        switch notice {
        case .setup: setupError = nil
        case .capture: captureError = nil
        case .silentInput: silentInputWarning = nil
        case .batch: batchError = nil
        }
    }

    /// Lo que se arregla fuera de Parla impide arrancar; pedir un permiso no,
    /// porque el propio arranque lanza el diálogo del sistema. Lo usa el menú
    /// emergente, que ya enseña los avisos y no necesita el panel.
    func isBlocked(_ mode: ParlaMode) -> Bool {
        setup.refreshNow()
        let blocked = !setup.status.startBlockers(for: mode).isEmpty
        blockedMode = blocked ? mode : nil
        return blocked
    }

    /// Desde un atajo: si falta algo, el panel lo enseña con su botón.
    private func canStart(_ mode: ParlaMode) -> Bool {
        guard !isBlocked(mode) else {
            showPanel()
            return false
        }
        return true
    }

    /// Las ventanas de Estudio y de la bienvenida. Se crea en `init` porque su
    /// contenido necesita a `self`.
    @ObservationIgnored private(set) var windows: WindowCoordinator!

    init() {
        windows = WindowCoordinator(
            studioContent: { [unowned self] router in
                AnyView(StudioView(state: self, router: router)
                    .modelContainer(Persistence.container))
            },
            welcomeContent: { AnyView(EmptyView()) })
        setup.startObserving()
        Task { await setup.refresh() }
    }

    private func makeExplainer(apiKey: String) -> ClaudeExplainer {
        ClaudeExplainer(builder: model.requestBuilder, apiKey: apiKey)
    }

    // MARK: - Estado del modo lote

    /// Frases oídas y todavía sin traducir. Sobreviven a apagar la escucha:
    /// apagar no manda nada, y perderlas sería perder la sesión entera.
    private(set) var pending: [Utterance] = []
    private(set) var isSendingBatch = false
    /// Los patrones del último lote. No son de ninguna frase: son del conjunto.
    private(set) var batchSummary: [String] = []
    private(set) var batchError: String?

    /// Las últimas primero, como las tarjetas.
    var pendingPreview: [Utterance] {
        Array(pending.sorted { $0.startedAt > $1.startedAt }.prefix(4))
    }

    var visibleCards: [CardPresentation] {
        // En lote las tarjetas llegan de veinte en veinte: recortar a tres
        // escondería justo lo que acabas de pedir.
        Self.mostRecent(cards, limit: mode == .batch ? 30 : 3)
    }

    /// Las más recientes primero, ordenadas por cuándo se dijo la frase y no por
    /// cuándo llegó la respuesta: las llamadas se resuelven desordenadas.
    ///
    /// La nueva entra arriba, pegada al texto en vivo, para no tener que buscar
    /// con la vista dónde apareció.
    static func mostRecent(_ cards: [CardPresentation],
                           limit: Int = 3) -> [CardPresentation] {
        Array(cards.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// No opcional a propósito: un store ausente perdía tarjetas en silencio.
    /// Nada de la UI depende de él, así que queda fuera de la observación.
    @ObservationIgnored
    private let store = CardStore(modelContainer: Persistence.container)

    private var engine: SpeechTranscriberEngine?
    private var pipelineTask: Task<Void, Never>?
    private var panel: FloatingPanel?
    @ObservationIgnored private let capturer = ScreenCapturer.live
    /// Mientras la cruz está abierta, otro atajo no abre una segunda.
    private var isSelectingRegion = false

    func toggleListening() {
        isListening ? stop() : start()
    }

    private func start() {
        // Los dos modos usan el reconocimiento de voz: uno apaga al otro.
        if isSubtitling { stopSubtitles() }
        guard canStart(.voice) else { return }
        // `hasAPIKey` dijo que hay clave, pero leerla puede fallar igual (se
        // canceló el diálogo del Llavero).
        guard let apiKey = KeychainStore.shared.apiKey else {
            setupError = ExplainerError.missingAPIKey.readableMessage
            showPanel()
            return
        }
        isListening = true
        setupError = nil
        showPanel()

        let engine = SpeechTranscriberEngine(
            source: AudioCapture(preferredInputUID: inputDeviceUID),
            locales: [Locale(identifier: "es-419"), Locale(identifier: "es-ES")])
        self.engine = engine
        let explainer = makeExplainer(apiKey: apiKey)
        let pipelineMode: SessionPipeline.Mode = mode == .batch ? .deferred : .immediate

        pipelineTask = Task {
            let phaseWatcher = Task { [weak self] in
                while !Task.isCancelled {
                    if case .downloadingModel(let fraction) = engine.phase {
                        self?.downloadProgress = fraction
                    } else {
                        self?.downloadProgress = nil
                    }
                    if engine.phase == .ready, !engine.isReceivingAudio {
                        self?.silentInputWarning =
                            "No llega audio desde \(engine.inputDeviceName). "
                            + "Si es un auricular Bluetooth, macOS puede tenerlo en "
                            + "modo solo salida: elige otra entrada en Ajustes del "
                            + "Sistema › Sonido."
                    } else {
                        self?.silentInputWarning = nil
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { phaseWatcher.cancel() }

            do {
                try await engine.start()
            } catch TranscriberSetupError.microphoneDenied {
                setup.refreshNow()
                blockedMode = .voice
                stop()
                showPanel()
                return
            } catch TranscriberSetupError.localeUnsupported {
                setupError = "Tu Mac no tiene un modelo de voz en español disponible."
                stop()
                showPanel()
                return
            } catch {
                Log.audio.error("no se pudo encender la escucha: \(error)")
                setupError = "No se pudo encender la escucha."
                stop()
                showPanel()
                return
            }

            let pipeline = SessionPipeline(transcriber: engine,
                                           explainer: explainer,
                                           mode: pipelineMode)
            for await output in pipeline.outputs {
                switch output {
                case .partial(let text):
                    Log.pipeline.info("parcial: \(text)")
                    partialText = text
                case .pending(let utterance):
                    Log.pipeline.info("frase en cola: \(utterance.text)")
                    partialText = ""
                    pending.append(utterance)
                case .card(let utterance, let card):
                    Log.pipeline.info("tarjeta lista para: \(utterance.text)")
                    partialText = ""
                    upsert(utterance, .ready(card))
                    await store.save(utterance: utterance, card: card)
                case .failure(let utterance, let error):
                    Log.pipeline.error("fallo en «\(utterance.text)»: \(error.readableMessage)")
                    partialText = ""
                    upsert(utterance, .failed(error))
                }
            }
        }
    }

    private func stop() {
        isListening = false
        partialText = ""
        downloadProgress = nil
        silentInputWarning = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        let engine = self.engine
        self.engine = nil
        Task { await engine?.stop() }
        // El panel se queda si hay frases en cola: ahí está el botón de
        // traducirlas, y apagar la escucha no las manda.
        if pending.isEmpty { hidePanel() }
    }

    func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
        blockedMode = nil
    }

    private func upsert(_ utterance: Utterance, _ state: CardState) {
        if let existing = cards.first(where: { $0.id == utterance.id }) {
            existing.state = state
        } else {
            cards.append(CardPresentation(utterance: utterance, state: state))
        }
        trimCards()
    }

    /// El panel guarda las 30 últimas. Al salir del búfer, la imagen de una
    /// captura deja de existir en memoria.
    private func trimCards() {
        if cards.count > 30 { cards.removeFirst(cards.count - 30) }
    }

    // MARK: - El lote

    /// Manda de una vez todo lo que se ha oído. Es el único gesto que gasta
    /// tokens en modo lote.
    func sendBatch() {
        guard !pending.isEmpty, !isSendingBatch else { return }
        guard let apiKey = KeychainStore.shared.apiKey else {
            batchError = ExplainerError.missingAPIKey.readableMessage
            showPanel()
            return
        }

        let batch = pending.sorted { $0.startedAt < $1.startedAt }
        pending = []
        batchSummary = []
        batchError = nil
        isSendingBatch = true
        showPanel()
        for utterance in batch { upsert(utterance, .pending) }

        let explainer = makeExplainer(apiKey: apiKey)
        Task {
            defer { isSendingBatch = false }

            let outcome: BatchOutcome
            do {
                outcome = try await explainer.explainBatch(batch)
            } catch let error as ExplainerError {
                returnToQueue(batch, error: error)
                return
            } catch {
                returnToQueue(batch, error: .network(error.localizedDescription))
                return
            }

            for utterance in batch {
                guard let card = outcome.cards[utterance.id] else {
                    // Sin tarjeta: o el modelo la descartó por no ser una frase,
                    // o falló y vuelve a la cola. En ambos casos, fuera del panel.
                    cards.removeAll { $0.id == utterance.id }
                    continue
                }
                upsert(utterance, .ready(card))
                await store.save(utterance: utterance, card: card)
            }

            batchSummary = outcome.summary
            Log.pipeline.info(
                "lote de \(batch.count): \(outcome.cards.count) tarjetas, "
                + "\(outcome.failures.count) fallos")

            if let first = outcome.failures.first {
                returnToQueue(outcome.failures.map(\.utterance), error: first.error)
            }
        }
    }

    func discardPending() {
        pending = []
        batchError = nil
        // Solo se cierra si no queda nada que leer: descartar la cola no es
        // motivo para llevarse por delante las tarjetas del lote anterior.
        if !isListening, cards.isEmpty { hidePanel() }
    }

    /// Lo que no recibió respuesta vuelve a la cola: el botón de traducir es su
    /// reintento. Nada se pierde en silencio.
    private func returnToQueue(_ utterances: [Utterance], error: ExplainerError) {
        for utterance in utterances { cards.removeAll { $0.id == utterance.id } }
        pending.append(contentsOf: utterances)
        pending.sort { $0.startedAt < $1.startedAt }
        batchError = utterances.count == 1
            ? error.readableMessage
            : "\(utterances.count) frases se quedaron sin traducir. \(error.readableMessage)"
    }

    // MARK: - Reintento de una tarjeta suelta

    func retry(_ presentation: CardPresentation) {
        if presentation.capture != nil {
            guard let apiKey = KeychainStore.shared.apiKey else { return }
            sendCapture(presentation, apiKey: apiKey)
            return
        }
        guard let apiKey = KeychainStore.shared.apiKey,
              let utterance = presentation.utterance
        else { return }
        presentation.state = .pending
        let explainer = makeExplainer(apiKey: apiKey)
        Task {
            do {
                if let card = try await explainer.explain(utterance) {
                    presentation.state = .ready(card)
                    await store.save(utterance: utterance, card: card)
                }
            } catch let error as ExplainerError {
                presentation.state = .failed(error)
            } catch {
                presentation.state = .failed(.network(error.localizedDescription))
            }
        }
    }

    // MARK: - Subtítulos del sistema

    func toggleSubtitles() {
        isSubtitling ? stopSubtitles() : startSubtitles()
    }

    private func startSubtitles() {
        if isListening { stop() }
        guard canStart(.subtitles) else { return }
        isSubtitling = true
        setupError = nil
        subtitleModel.notice = nil
        subtitleModel.frame = nil
        subtitleModel.isVisible = false
        showSubtitleOverlay()

        subtitleTask = Task {
            let readiness = await LiveTranslator.readiness()
            if let notice = LiveTranslator.notice(for: readiness) {
                subtitleModel.notice = notice
                await setup.refresh()
                blockedMode = .subtitles
                showPanel()
                try? await Task.sleep(for: .seconds(6))
                stopSubtitles()
                return
            }

            let engine = SpeechTranscriberEngine(
                source: SystemAudioCapture(),
                locales: [Locale(identifier: "en-US"), Locale(identifier: "en-GB")],
                logsText: false)
            subtitleEngine = engine
            let downloadWatcher = Task { [weak self] in
                while !Task.isCancelled {
                    if case .downloadingModel(let fraction) = engine.phase {
                        self?.subtitleModel.notice =
                            "Descargando el modelo de inglés… \(Int(fraction * 100)) %"
                    } else if self?.subtitleModel.notice?.hasPrefix("Descargando") == true {
                        self?.subtitleModel.notice = nil
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { downloadWatcher.cancel() }

            do {
                try await engine.start()
            } catch TranscriberSetupError.screenRecordingDenied {
                // Igual que la captura: el diálogo del sistema, una sola vez.
                setup.screenRecordingWasDenied()
                blockedMode = .subtitles
                showPanel()
                stopSubtitles()
                return
            } catch {
                // Apagados mientras arrancaban: no es un error que enseñar.
                guard isSubtitling, !(error is CancellationError) else { return }
                Log.audio.error("no se pudieron encender los subtítulos: \(error)")
                setupError = "No se pudieron encender los subtítulos."
                showPanel()
                stopSubtitles()
                return
            }
            Log.pipeline.info("subtítulos encendidos")

            let speaker = SubtitleSpeaker()
            subtitleSpeaker = speaker
            let pipeline = SubtitlePipeline(transcriber: engine, translator: LiveTranslator())
            for await output in pipeline.outputs {
                guard isSubtitling else { break }
                switch output {
                case .show(let frame):
                    subtitleModel.notice = nil
                    subtitleModel.frame = frame
                    subtitleModel.isVisible = true
                case .hide:
                    subtitleModel.isVisible = false
                case .line(let line):
                    Log.pipeline.info("subtítulos: frase guardada")
                    // Solo lo traducido: el inglés de una traducción fallida no se lee.
                    if readsSubtitlesAloud, !line.spanish.isEmpty { speaker.say(line.spanish) }
                    await store.save(subtitle: line)
                }
            }
            // El stream terminó sin que nadie apagara: el audio se cortó y no volvió.
            if isSubtitling {
                setupError = "El audio del sistema se cortó y se apagaron los subtítulos."
                showPanel()
                stopSubtitles()
            }
        }
    }

    func stopSubtitles() {
        guard isSubtitling else { return }
        isSubtitling = false
        subtitleTask?.cancel()
        subtitleTask = nil
        let engine = subtitleEngine
        subtitleEngine = nil
        Task { await engine?.stop() }
        subtitleSpeaker?.stop()
        subtitleSpeaker = nil
        subtitleOverlay?.orderOut(nil)
        subtitleOverlay = nil
        subtitleModel.frame = nil
        subtitleModel.isVisible = false
        Log.pipeline.info("subtítulos apagados")
    }

    /// En la pantalla donde está el ratón al encenderlos.
    private func showSubtitleOverlay() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main
        else { return }
        let overlay = SubtitleOverlay(model: subtitleModel, screen: screen)
        overlay.orderFrontRegardless()
        subtitleOverlay = overlay
    }

    // MARK: - Captura de pantalla

    /// La clave se comprueba antes de abrir la cruz: seleccionar una región
    /// para luego enterarse de que falta la clave es trabajo tirado.
    func captureScreen() {
        guard !isSelectingRegion else { return }
        guard canStart(.capture) else { return }
        guard let apiKey = KeychainStore.shared.apiKey else {
            setupError = ExplainerError.missingAPIKey.readableMessage
            showPanel()
            return
        }
        isSelectingRegion = true
        captureError = nil

        Task {
            defer { isSelectingRegion = false }

            let png: Data?
            do {
                png = try await grabRegion()
            } catch ScreenCapturer.Failure.noPermission {
                setup.screenRecordingWasDenied()
                blockedMode = .capture
                showPanel()
                return
            } catch {
                Log.pipeline.error("no se pudo capturar la pantalla: \(error)")
                captureError = "No se pudo capturar la pantalla."
                showPanel()
                return
            }
            // Esc: ni tarjeta, ni coste, ni mensaje.
            guard let png else { return }

            let prepared: ImageDownscaler.Prepared
            do {
                prepared = try ImageDownscaler.prepare(png)
            } catch ImageDownscaler.Failure.tooLarge {
                captureError = "La región es demasiado grande. Selecciona menos."
                showPanel()
                return
            } catch {
                captureError = "No se pudo leer la captura."
                showPanel()
                return
            }

            let presentation = CardPresentation(capture: Capture(
                imageData: prepared.data, mediaType: prepared.mediaType, capturedAt: Date()))
            cards.append(presentation)
            trimCards()
            showPanel()
            sendCapture(presentation, apiKey: apiKey)
        }
    }

    /// `PARLA_CAPTURE_FILE` salta la selección y usa ese archivo: así se prueba
    /// el flujo entero desde la terminal, sin ratón y sin permiso de pantalla.
    /// La ruta tiene que estar dentro del contenedor del sandbox.
    private func grabRegion() async throws -> Data? {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["PARLA_CAPTURE_FILE"] {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
        #endif
        return try await capturer.captureRegion()
    }

    /// «¿No era eso?»: la misma imagen, con el caso que el usuario eligió.
    func reclassify(_ presentation: CardPresentation, as kind: CaptureKind) {
        guard let apiKey = KeychainStore.shared.apiKey else { return }
        presentation.forcedKind = kind
        sendCapture(presentation, apiKey: apiKey)
    }

    private func sendCapture(_ presentation: CardPresentation, apiKey: String) {
        guard let capture = presentation.capture else { return }
        presentation.state = .pending
        let explainer = makeExplainer(apiKey: apiKey)
        let forced = presentation.forcedKind
        Task {
            do {
                let card = try await explainer.explainCapture(capture, forcing: forced)
                // Solo el caso: el texto de la pantalla no va al log del sistema,
                // que se guarda fuera del contenedor y acaba en los sysdiagnose.
                Log.pipeline.info("captura: \(card.kind.rawValue)")
                presentation.state = .readyCapture(card)
                await store.save(capture: capture, card: card)
            } catch let error as ExplainerError {
                Log.pipeline.error("captura fallida: \(error.readableMessage)")
                presentation.state = .failed(error)
            } catch {
                presentation.state = .failed(.network(error.localizedDescription))
            }
        }
    }

    private func showPanel() {
        guard panel == nil else { return }
        let panel = FloatingPanel { PanelView(state: self) }
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
