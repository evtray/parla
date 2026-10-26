import AVFoundation
import NaturalLanguage
import ParlaCore

/// Lee frases en voz alta: el español de los subtítulos y el inglés de las
/// capturas, cada uno con una voz de su idioma.
///
/// El audio se genera y se reproduce dentro de Parla (`write` y un
/// `AVAudioEngine` propio) en lugar de con `speak`: ScreenCaptureKit excluye el
/// audio de Parla, así que no oye su propia voz ni intenta transcribirla como
/// inglés.
@MainActor
final class Speaker {

    struct VoiceOption: Equatable, Sendable {
        let identifier: String
        let language: String
        /// Como `AVSpeechSynthesisVoiceQuality`: 1 normal, 2 mejorada, 3 premium.
        let quality: Int
    }

    /// Una voz de `language` (código de dos letras). En español, el acento
    /// latinoamericano primero, y si no hay, el de España; en inglés, el
    /// estadounidense. Dentro del acento, las voces estándar de Apple antes que
    /// las de efecto (`eloquence`: Eddy, Flo, Grandma…, que suenan robóticas),
    /// y luego la mejor calidad.
    nonisolated static func bestVoice(among voices: [VoiceOption],
                                      language: String = "es") -> VoiceOption? {
        func preferredAccent(_ voice: VoiceOption) -> Bool {
            switch language {
            case "es": voice.language != "es-ES"
            case "en": voice.language == "en-US"
            default: true
            }
        }
        func rank(_ voice: VoiceOption) -> (Int, Int, Int) {
            (preferredAccent(voice) ? 1 : 0,
             voice.identifier.contains(".eloquence.") ? 0 : 1,
             voice.quality)
        }
        return voices
            .filter { $0.language.hasPrefix(language) }
            .max { a, b in
                // A igualdad, la de identificador menor, para que la elección
                // no dependa del orden en que el sistema las lista.
                rank(a) != rank(b) ? rank(a) < rank(b) : a.identifier > b.identifier
            }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let voice: AVSpeechSynthesisVoice?
    private var queue = SpeechQueue()
    private var connectedFormat: AVAudioFormat?
    /// Cambia al callar: descarta lo que llegue de una frase cortada.
    private var generation = 0
    private var pendingBuffers = 0
    private var synthesisDone = false

    /// El idioma en que se escribió `text`, para elegir con qué voz leerlo. Una
    /// captura de «entender» puede venir en francés; sin pistas, inglés.
    nonisolated static func language(of text: String) -> String {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en"
    }

    let language: String

    init(language: String = "es") {
        self.language = language
        let options = AVSpeechSynthesisVoice.speechVoices().map {
            VoiceOption(identifier: $0.identifier, language: $0.language,
                        quality: $0.quality.rawValue)
        }
        voice = Self.bestVoice(among: options, language: language)
            .flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
        engine.attach(player)
        Log.audio.info("voz para «\(language)»: \(voice?.language ?? "ninguna")")
    }

    func say(_ text: String) {
        if let next = queue.enqueue(text) { speak(next) }
    }

    /// Calla en el acto y olvida lo pendiente.
    func stop() {
        generation += 1
        queue = SpeechQueue()
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        engine.stop()
        pendingBuffers = 0
        synthesisDone = false
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // El español de los subtítulos, un poco más rápido que lo normal: suele
        // ser más largo que el inglés que traduce y tiene que seguirle el paso.
        // El inglés de una captura se escucha para aprenderlo: a ritmo normal.
        let speed: Float = language == "es" ? 1.15 : 1
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             AVSpeechUtteranceDefaultSpeechRate * speed)
        let current = generation
        pendingBuffers = 0
        synthesisDone = false
        // @Sendable explícito: el sintetizador llama desde su propio hilo, y un
        // cierre que heredara @MainActor abortaría al comprobar el executor.
        synthesizer.write(utterance) { @Sendable [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            let chunk = AudioChunk(buffer: pcm)
            Task { @MainActor in self?.receive(chunk, generation: current) }
        }
    }

    private func receive(_ chunk: AudioChunk, generation: Int) {
        guard generation == self.generation else { return }
        let buffer = chunk.buffer
        // Un buffer vacío marca el final de la síntesis.
        guard buffer.frameLength > 0 else {
            synthesisDone = true
            finishIfDone()
            return
        }
        if connectedFormat != buffer.format {
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            connectedFormat = buffer.format
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log.audio.error("no se pudo reproducir la voz: \(error.localizedDescription)")
                return
            }
        }
        pendingBuffers += 1
        player.scheduleBuffer(buffer) { @Sendable [weak self] in
            Task { @MainActor in self?.played(generation: generation) }
        }
        if !player.isPlaying { player.play() }
    }

    private func played(generation: Int) {
        guard generation == self.generation else { return }
        pendingBuffers -= 1
        finishIfDone()
    }

    private func finishIfDone() {
        guard synthesisDone, pendingBuffers == 0 else { return }
        synthesisDone = false
        if let next = queue.finished() { speak(next) }
    }
}
