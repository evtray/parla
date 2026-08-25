import AppKit
import Foundation
import Observation
import ParlaCore

@MainActor
@Observable
final class AppState {
    private(set) var isListening = false
    private(set) var partialText = ""
    private(set) var setupError: String?
    private(set) var needsMicrophoneAccess = false
    private(set) var downloadProgress: Double?

    private var engine: SpeechTranscriberEngine?
    private var listener: Task<Void, Never>?

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
        isListening = true
        setupError = nil
        let engine = SpeechTranscriberEngine()
        self.engine = engine

        listener = Task {
            let phaseWatcher = Task { [weak self] in
                while !Task.isCancelled {
                    if case .downloadingModel(let fraction) = engine.phase {
                        self?.downloadProgress = fraction
                    } else {
                        self?.downloadProgress = nil
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

            for await (event, _) in engine.events {
                switch event {
                case .partial(let text), .final(let text):
                    if !text.isEmpty { partialText = text }
                }
            }
        }
    }

    private func stop() {
        isListening = false
        downloadProgress = nil
        listener?.cancel()
        listener = nil
        let engine = self.engine
        self.engine = nil
        Task { await engine?.stop() }
    }
}
