import AVFoundation
import CoreGraphics
import CoreMedia
@preconcurrency import ScreenCaptureKit

/// Todo el audio del sistema, menos el de la propia Parla, vía ScreenCaptureKit.
/// Usa el permiso de Grabación de pantalla que Parla ya tiene para las capturas.
@MainActor
final class SystemAudioCapture: NSObject, AudioSource {

    let displayName = "el audio del sistema"

    private var stream: SCStream?
    private var output: SystemAudioOutput?
    /// Un solo reintento cuando el stream se corta (reposo, cambio de pantalla).
    private var retried = false

    var isReceivingAudio: Bool { output?.receivedRecently ?? false }

    func requestAccess() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw TranscriberSetupError.screenRecordingDenied
        }
    }

    nonisolated static func configuration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        // ScreenCaptureKit exige vídeo: el mínimo, y sin salida que lo reciba.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        return configuration
    }

    func start(outputFormat: AVAudioFormat) async throws -> AsyncStream<AudioChunk> {
        stop()
        let (chunks, continuation) = AsyncStream<AudioChunk>.makeStream()
        let output = SystemAudioOutput(outputFormat: outputFormat, continuation: continuation)
        self.output = output
        retried = false
        try await startStream(with: output)
        return chunks
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
        output?.finish()
        output = nil
    }

    private func startStream(with output: SystemAudioOutput) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw TranscriberSetupError.assetUnavailable
        }
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: Self.configuration(),
                              delegate: self)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        // Si stop() llegó mientras arrancaba, este stream ya no tiene dueño.
        guard self.output === output else {
            try? await stream.stopCapture()
            return
        }
        self.stream = stream
        Log.audio.info("audio del sistema: capturando")
    }

    /// Un reintento; si vuelve a fallar se cierra el stream de audio, el motor
    /// termina y `AppState` apaga los subtítulos con un aviso.
    fileprivate func recover(from error: any Error) {
        Log.audio.error("el audio del sistema se cortó: \(error.localizedDescription)")
        guard !retried, let output else {
            output?.finish()
            return
        }
        retried = true
        Task {
            do {
                try await startStream(with: output)
            } catch {
                output.finish()
            }
        }
    }
}

extension SystemAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in self.recover(from: error) }
    }
}

/// Recibe los buffers en la cola de ScreenCaptureKit y los entrega ya en el
/// formato del analizador.
final class SystemAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.schoolaid.Parla.audio-del-sistema")
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AudioChunk>.Continuation
    /// Solo se toca desde `queue`.
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var lastBufferAt: Date?

    init(outputFormat: AVAudioFormat, continuation: AsyncStream<AudioChunk>.Continuation) {
        self.outputFormat = outputFormat
        self.continuation = continuation
    }

    var receivedRecently: Bool {
        lock.withLock { lastBufferAt.map { Date().timeIntervalSince($0) < 3 } ?? false }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, let pcm = AudioConversion.pcmBuffer(from: sampleBuffer) else { return }
        if converter == nil || converter?.inputFormat != pcm.format {
            converter = AVAudioConverter(from: pcm.format, to: outputFormat)
        }
        if let converted = AudioConversion.convert(pcm, to: outputFormat, using: converter) {
            continuation.yield(AudioChunk(buffer: converted))
        }
        lock.withLock { lastBufferAt = Date() }
    }

    func finish() { continuation.finish() }
}
