import AVFoundation
import Observation

/// Transporta un buffer de audio entre el hilo de captura y el consumidor.
///
/// `AVAudioPCMBuffer` no es `Sendable`, pero aquí la transferencia es exclusiva:
/// el buffer se crea en la conversión y nadie más lo vuelve a tocar. Es la misma
/// asunción que hace Apple en `AnalyzerInput`, declarado `@unchecked Sendable`.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

@MainActor
@Observable
final class AudioCapture {

    /// Nivel RMS 0…1 para el indicador de "te estoy oyendo".
    private(set) var level: Float = 0

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var converter: AVAudioConverter?
    private var observer: (any NSObjectProtocol)?

    func start(outputFormat: AVAudioFormat) throws -> AsyncStream<AudioChunk> {
        stop()

        let stream = AsyncStream<AudioChunk> { continuation in
            self.continuation = continuation
        }
        try installTap(outputFormat: outputFormat)

        // Auriculares desconectados, cambio de entrada: reconstruir el tap.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                try? self.installTap(outputFormat: outputFormat)
            }
        }
        return stream
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        removeTapAndStop()
        continuation?.finish()
        continuation = nil
        converter = nil
        level = 0
    }

    /// El tap y el motor son estados independientes: un cambio de configuración
    /// de audio detiene el motor pero deja el tap instalado. Condicionar la
    /// retirada a `isRunning` dejaba el tap vivo, y la reinstalación abortaba el
    /// proceso con 'required condition is false: nullptr == Tap()'.
    /// `removeTap` sobre un bus sin tap es inocuo, así que se llama siempre.
    private func removeTapAndStop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    private func installTap(outputFormat: AVAudioFormat) throws {
        removeTapAndStop()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        self.converter = converter

        let continuation = self.continuation

        // CoreAudio invoca este bloque desde su hilo de tiempo real. Tiene que
        // ser @Sendable de forma explícita: si hereda el aislamiento @MainActor
        // de la clase, el runtime de Swift comprueba el executor en cada buffer,
        // ve que no está en el hilo principal y aborta con SIGTRAP.
        let tap: AVAudioNodeTapBlock = { @Sendable [weak self] buffer, _ in
            let rms = Self.rms(of: buffer)
            if let converted = Self.convert(buffer, to: outputFormat, using: converter) {
                continuation?.yield(AudioChunk(buffer: converted))
            }
            Task { @MainActor in self?.level = rms }
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: tap)
        engine.prepare()
        try engine.start()
    }

    /// Puras y sin estado: corren en el hilo de audio, nunca en el principal.
    private nonisolated static func convert(_ buffer: AVAudioPCMBuffer,
                                to format: AVAudioFormat,
                                using converter: AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        return min(1, (sum / Float(count)).squareRoot() * 8)
    }
}
