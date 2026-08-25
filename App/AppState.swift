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

    var visibleCards: [CardPresentation] { Self.mostRecent(cards) }

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

            let pipeline = SessionPipeline(transcriber: engine, explainer: explainer)
            for await output in pipeline.outputs {
                switch output {
                case .partial(let text):
                    Log.pipeline.info("parcial: \(text)")
                    partialText = text
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
