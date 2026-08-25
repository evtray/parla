import AVFoundation
import Foundation
import Speech
import ParlaCore

enum TranscriberSetupError: Error {
    case microphoneDenied
    case localeUnsupported
    case assetUnavailable
}

enum TranscriberPhase: Sendable, Equatable {
    case idle
    /// Fracción 0…1 de la descarga del modelo de español.
    case downloadingModel(Double)
    case ready
    case failed(String)
}

/// Transcripción en el dispositivo con la API de macOS 26.
/// El audio nunca sale de la máquina.
@MainActor
final class SpeechTranscriberEngine: Transcriber {

    /// Creado en `init` para poder ser `nonisolated let`: así satisface el
    /// requisito síncrono del protocolo `Transcriber`.
    nonisolated let events: AsyncStream<(TranscriptEvent, Date)>
    private nonisolated let relay: AsyncStream<(TranscriptEvent, Date)>.Continuation

    private let requestedLocale: Locale
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audio: AudioCapture?
    private var pump: Task<Void, Never>?

    /// Fase de arranque, para que la UI pueda mostrar descarga o error.
    private(set) var phase: TranscriberPhase = .idle

    init(locale: Locale = Locale(identifier: "es-419")) {
        self.requestedLocale = locale
        (self.events, self.relay) = AsyncStream.makeStream()
    }

    func start() async throws {
        guard await Self.microphoneGranted() else {
            phase = .failed("micrófono denegado")
            throw TranscriberSetupError.microphoneDenied
        }
        let locale = try await resolvedLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        try await ensureAssets(for: transcriber)
        _ = try? await AssetInventory.reserve(locale: locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else { throw TranscriberSetupError.assetUnavailable }

        let capture = AudioCapture()
        let chunks = try capture.start(outputFormat: format)
        let inputs = chunks.map { AnalyzerInput(buffer: $0.buffer) }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: inputs)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.audio = capture
        phase = .ready

        pump = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self.emit(result.isFinal ? .final(text) : .partial(text))
                }
            } catch {
                self.emit(.final(""))   // cierra lo pendiente
            }
        }
    }

    /// El micrófono se pide explícitamente para poder distinguir "denegado" de
    /// "no hay audio" y ofrecerle al usuario el botón a Ajustes del Sistema.
    private static func microphoneGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func stop() async {
        pump?.cancel()
        pump = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        transcriber = nil
        audio?.stop()
        audio = nil
        phase = .idle
    }

    private nonisolated func emit(_ event: TranscriptEvent) {
        relay.yield((event, Date()))
    }

    /// `es-419` puede no estar; la API resuelve al equivalente soportado.
    private func resolvedLocale() async throws -> Locale {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) {
            return match
        }
        if let fallback = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "es-ES")
        ) { return fallback }
        throw TranscriberSetupError.localeUnsupported
    }

    /// Descarga el modelo de español si no está instalado.
    private func ensureAssets(for module: SpeechTranscriber) async throws {
        switch await AssetInventory.status(forModules: [module]) {
        case .installed:
            return
        case .unsupported:
            throw TranscriberSetupError.assetUnavailable
        case .supported, .downloading:
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [module]
            ) else { return }
            phase = .downloadingModel(0)
            let progress = request.progress
            let watcher = Task { [weak self] in
                while !Task.isCancelled {
                    await MainActor.run { self?.phase = .downloadingModel(progress.fractionCompleted) }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { watcher.cancel() }
            try await request.downloadAndInstall()
        @unknown default:
            throw TranscriberSetupError.assetUnavailable
        }
    }
}
