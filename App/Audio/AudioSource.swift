@preconcurrency import AVFoundation
import CoreMedia

/// De dónde llega el audio que se transcribe: el micrófono o el sistema.
@MainActor
protocol AudioSource: AnyObject {
    /// Para los avisos: «No llega audio desde …».
    var displayName: String { get }
    var isReceivingAudio: Bool { get }
    /// Lanza el `TranscriberSetupError` que toque si falta el permiso.
    func requestAccess() async throws
    func start(outputFormat: AVAudioFormat) async throws -> AsyncStream<AudioChunk>
    func stop()
}

/// Conversiones de audio compartidas por las dos fuentes. Puras: corren en el
/// hilo de audio, nunca en el principal.
enum AudioConversion {

    nonisolated static func convert(_ buffer: AVAudioPCMBuffer,
                                    to format: AVAudioFormat,
                                    using converter: AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        // El bloque corre dentro de `convert`, de forma síncrona: no hay concurrencia real.
        nonisolated(unsafe) var consumed = false
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

    /// Lo que entrega ScreenCaptureKit, como buffer de AVFAudio.
    nonisolated static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
