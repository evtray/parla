import AppKit
import Foundation
import Observation
import SwiftData
import ParlaCore

@MainActor
@Observable
final class AppState {

    private(set) var isListening = false
    private(set) var partialText = ""
    private(set) var setupError: String?
    private(set) var needsMicrophoneAccess = false
    private(set) var downloadProgress: Double?
    /// Mensaje visible cuando el dispositivo de entrada no entrega audio.
    private(set) var silentInputWarning: String?
    private(set) var cards: [CardPresentation] = []

    /// Se persiste al cambiarlo: el modo sobrevive a cerrar la app.
    var mode: TranslationMode = Preferences.translationMode {
        didSet { Preferences.translationMode = mode }
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
        Array(cards.sorted { $0.utterance.startedAt > $1.utterance.startedAt }.prefix(limit))
    }

    /// No opcional a propósito: un store ausente perdía tarjetas en silencio.
    /// Nada de la UI depende de él, así que queda fuera de la observación.
    @ObservationIgnored
    private let store = CardStore(modelContainer: Persistence.container)

    private var engine: SpeechTranscriberEngine?
    private var pipelineTask: Task<Void, Never>?
    private var panel: FloatingPanel?

    func toggleListening() {
        isListening ? stop() : start()
    }

    /// Abre el panel de Privacidad › Micrófono directamente.
    static func openMicrophoneSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    private func start() {
        guard let apiKey = KeychainStore.shared.apiKey else {
            setupError = ExplainerError.missingAPIKey.readableMessage
            showPanel()
            return
        }
        isListening = true
        setupError = nil
        showPanel()

        let engine = SpeechTranscriberEngine()
        self.engine = engine
        let explainer = ClaudeExplainer(apiKey: apiKey)
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
                needsMicrophoneAccess = false
            } catch TranscriberSetupError.microphoneDenied {
                needsMicrophoneAccess = true
                setupError = "Parla necesita acceso al micrófono."
                stop()
                return
            } catch TranscriberSetupError.localeUnsupported {
                setupError = "Tu Mac no tiene un modelo de voz en español disponible."
                stop()
                return
            } catch {
                setupError = String(describing: error)
                stop()
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
    }

    private func upsert(_ utterance: Utterance, _ state: CardState) {
        if let existing = cards.first(where: { $0.id == utterance.id }) {
            existing.state = state
        } else {
            cards.append(CardPresentation(utterance: utterance, state: state))
        }
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

        let explainer = ClaudeExplainer(apiKey: apiKey)
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
        guard let apiKey = KeychainStore.shared.apiKey else { return }
        presentation.state = .pending
        let explainer = ClaudeExplainer(apiKey: apiKey)
        Task {
            do {
                if let card = try await explainer.explain(presentation.utterance) {
                    presentation.state = .ready(card)
                    await store.save(utterance: presentation.utterance, card: card)
                }
            } catch let error as ExplainerError {
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
