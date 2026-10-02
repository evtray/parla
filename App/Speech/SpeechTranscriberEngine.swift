import AVFoundation
import Foundation
import Speech
import ParlaCore

enum TranscriberSetupError: Error {
    case microphoneDenied
    case screenRecordingDenied
    case localeUnsupported
    case assetUnavailable
}

enum TranscriberPhase: Sendable, Equatable {
    case idle
    /// Fracción 0…1 de la descarga del modelo de voz.
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

    private let source: any AudioSource
    /// En orden de preferencia: el primero que el sistema soporte.
    private let locales: [Locale]
    /// `false` para el audio del sistema: el texto de lo que suena no va al log.
    private let logsText: Bool

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var pump: Task<Void, Never>?

    /// Fase de arranque, para que la UI pueda mostrar descarga o error.
    private(set) var phase: TranscriberPhase = .idle

    var isReceivingAudio: Bool { source.isReceivingAudio }
    var inputDeviceName: String { source.displayName }

    init(source: any AudioSource, locales: [Locale], logsText: Bool = true) {
        self.source = source
        self.locales = locales
        self.logsText = logsText
        (self.events, self.relay) = AsyncStream.makeStream()
    }

    func start() async throws {
        do {
            try await source.requestAccess()
        } catch {
            phase = .failed("permiso denegado")
            throw error
        }
        let locale = try await resolvedLocale()
        Log.speech.info("locale resuelto: \(locale.identifier)")
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        try await ensureAssets(for: transcriber)
        _ = try? await AssetInventory.reserve(locale: locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else { throw TranscriberSetupError.assetUnavailable }
        Log.speech.info("formato del analizador: \(format.sampleRate) Hz, \(format.channelCount) canal(es)")

        let chunks = try await source.start(outputFormat: format)
        let inputs = chunks.map { AnalyzerInput(buffer: $0.buffer) }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: inputs)

        self.transcriber = transcriber
        self.analyzer = analyzer
        phase = .ready
        Log.speech.info("analizador arrancado")

        pump = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if self.logsText {
                        Log.speech.info("resultado \(result.isFinal ? "final" : "parcial"): \(text)")
                    } else {
                        Log.speech.info("resultado \(result.isFinal ? "final" : "parcial"): "
                            + "\(text.count) caracteres")
                    }
                    self.emit(result.isFinal ? .final(text) : .partial(text))
                }
                Log.speech.info("el stream de resultados terminó")
            } catch {
                Log.speech.error("el stream de resultados falló: \(String(describing: error))")
                self.emit(.final(""))   // cierra lo pendiente
            }
        }
    }

    func stop() async {
        pump?.cancel()
        pump = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        transcriber = nil
        source.stop()
        phase = .idle
    }

    private nonisolated func emit(_ event: TranscriptEvent) {
        relay.yield((event, Date()))
    }

    /// El primer idioma de la lista que el sistema soporte, en su variante
    /// equivalente (`es-419` puede resolverse a otra).
    private func resolvedLocale() async throws -> Locale {
        for locale in locales {
            if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                return match
            }
        }
        throw TranscriberSetupError.localeUnsupported
    }

    /// Descarga el modelo del idioma si no está instalado.
    private func ensureAssets(for module: SpeechTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [module])
        Log.speech.info("estado del modelo: \(String(describing: status))")
        switch status {
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
