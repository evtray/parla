import AudioToolbox
import AVFoundation
import CoreAudio
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

    /// Cuándo llegó el último buffer. Un dispositivo Bluetooth en modo A2DP
    /// acepta el tap y no entrega nada: sin esto, el fallo es invisible.
    private(set) var lastBufferAt: Date?

    /// Nombre del dispositivo de entrada, para poder decir cuál está mudo.
    var inputDeviceName: String {
        forcedInputName
            ?? AVCaptureDevice.default(for: .audio)?.localizedName
            ?? "el micrófono"
    }

    /// UID del micrófono elegido en Ajustes; `nil` deja el del sistema.
    private let preferredInputUID: String?
    /// El micro que se fijó a mano en el nodo de entrada, si se fijó alguno.
    private var forcedInputName: String?

    init(preferredInputUID: String? = nil) {
        self.preferredInputUID = preferredInputUID
    }

    /// `false` si el motor lleva más de 3 s sin recibir audio.
    var isReceivingAudio: Bool {
        guard let lastBufferAt else { return false }
        return Date().timeIntervalSince(lastBufferAt) < 3
    }

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
        lastBufferAt = nil
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
        // Antes de leer el formato: el formato es el del dispositivo, y leído
        // primero sería el del micro anterior.
        selectInputDevice(on: input)
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
            if let converted = AudioConversion.convert(buffer, to: outputFormat, using: converter) {
                continuation?.yield(AudioChunk(buffer: converted))
            }
            Task { @MainActor in
                self?.level = rms
                self?.lastBufferAt = Date()
            }
            AudioCapture.reportLevel(rms)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: tap)
        engine.prepare()
        try engine.start()
        Log.audio.info("tap instalado en \(inputDeviceName); "
            + "entrada \(inputFormat.sampleRate) Hz "
            + "\(inputFormat.channelCount)ch; motor corriendo: \(engine.isRunning)")
    }

    /// Sin micro elegido no se toca nada y el motor sigue al del sistema, como
    /// siempre. Con uno elegido se fija en el nodo de entrada; si ya no está
    /// conectado se fija el del sistema de forma explícita, porque el nodo
    /// podría seguir apuntando al que se acaba de desenchufar.
    private func selectInputDevice(on input: AVAudioInputNode) {
        forcedInputName = nil
        guard let preferredInputUID else { return }

        let devices = AudioDevices.all()
        let chosen = AudioDevices.input(preferredUID: preferredInputUID, among: devices)
        if chosen == nil {
            Log.audio.info("el micrófono elegido no está conectado; se usa el del sistema")
        }
        guard let target = chosen?.id ?? AudioDevices.defaultInput,
              let unit = input.audioUnit
        else { return }

        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var current = AudioDeviceID(kAudioObjectUnknown)
        var currentSize = size
        AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &current, &currentSize)

        // Fijar el dispositivo provoca un cambio de configuración, que vuelve a
        // pasar por aquí: si ya es el que toca, no se toca.
        if current != target {
            var id = target
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                              kAudioUnitScope_Global, 0, &id, size)
            guard status == noErr else {
                Log.audio.error("no se pudo fijar el micrófono: OSStatus \(status)")
                return
            }
        }
        forcedInputName = devices.first { $0.id == target }?.name
    }

    /// Puras y sin estado: corren en el hilo de audio, nunca en el principal.
    /// Un resumen cada ~5 s: sirve para distinguir "no te oigo" de "no entiendo".
    private nonisolated static let levelReporter = LevelReporter()

    private nonisolated static func reportLevel(_ rms: Float) {
        levelReporter.record(rms)
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

/// Acumula el nivel de entrada y lo registra periódicamente, sin inundar el log.
final class LevelReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var buffers = 0
    private var lastReport = Date()

    func record(_ rms: Float) {
        lock.lock()
        peak = max(peak, rms)
        buffers += 1
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 5 else { lock.unlock(); return }
        let (p, n) = (peak, buffers)
        peak = 0; buffers = 0; lastReport = now
        lock.unlock()
        Log.audio.info("entrada: \(n) buffers en 5s, pico \(String(format: "%.3f", p))")
    }
}

extension AudioCapture: AudioSource {
    var displayName: String { inputDeviceName }

    /// Se pide explícitamente para distinguir "denegado" de "no hay audio" y
    /// ofrecer el botón a Ajustes del Sistema.
    func requestAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
        default:
            break
        }
        throw TranscriberSetupError.microphoneDenied
    }
}
