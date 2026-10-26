import Testing
import AVFoundation
@testable import Parla

@Test func convierteDe48kA16kHz() throws {
    let source = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                            channels: 1, interleaved: false))
    let target = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                            channels: 1, interleaved: false))
    let input = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4800))
    input.frameLength = 4800
    for index in 0 ..< 4800 { input.floatChannelData![0][index] = sin(Float(index) * 0.05) }

    let output = try #require(AudioConversion.convert(
        input, to: target, using: AVAudioConverter(from: source, to: target)))
    #expect(output.format.sampleRate == 16_000)
    // Un tercio de los frames (1600), menos los ~240 que el conversor retiene
    // al arrancar y entrega con el buffer siguiente.
    #expect(output.frameLength > 1200 && output.frameLength <= 1600)
}

@Test @MainActor func elMicrofonoEsUnaFuenteDeAudio() {
    let source: any AudioSource = AudioCapture()
    #expect(!source.displayName.isEmpty)
    #expect(!source.isReceivingAudio)
}
