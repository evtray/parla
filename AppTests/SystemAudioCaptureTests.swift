import Testing
import ScreenCaptureKit
@testable import Parla

@Test func pideSoloAudioYSinElDeParla() {
    let configuration = SystemAudioCapture.configuration()
    #expect(configuration.capturesAudio)
    #expect(configuration.excludesCurrentProcessAudio)
    #expect(configuration.sampleRate == 48_000)
    #expect(configuration.channelCount == 1)
    // El vídeo es obligatorio en ScreenCaptureKit: se pide el mínimo.
    #expect(configuration.width == 2 && configuration.height == 2)
}
