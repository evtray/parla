import Testing
import AVFoundation
@testable import Parla

/// Una fuente de audio sin audio: el test decide cuándo se acaba y si el
/// arranque se queda esperando, para simular uno lento.
@MainActor
private final class FakeAudioSource: AudioSource {
    let displayName = "fuente de prueba"
    var isReceivingAudio = false
    private(set) var stopCalls = 0
    var holdStart = false
    /// Mientras `holdStart`, el arranque espera aquí a que el test lo suelte.
    private(set) var gate: CheckedContinuation<Void, Never>?
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    func requestAccess() async throws {}

    func start(outputFormat: AVAudioFormat) async throws -> AsyncStream<AudioChunk> {
        if holdStart { await withCheckedContinuation { gate = $0 } }
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() {
        stopCalls += 1
        continuation?.finish()
    }

    func endAudio() { continuation?.finish() }
}

@MainActor
private func englishEngine(_ source: FakeAudioSource) -> SpeechTranscriberEngine {
    SpeechTranscriberEngine(source: source, locales: [Locale(identifier: "en-US")], logsText: false)
}

@Test @MainActor func cuandoLaFuenteSeAcabaLosEventosTerminan() async throws {
    // Si el audio del sistema se corta y no vuelve, el modo tiene que poder
    // apagarse con aviso: para eso el stream de eventos tiene que terminar.
    let source = FakeAudioSource()
    let engine = englishEngine(source)
    try await engine.start()
    source.endAudio()

    let ended = await withTaskGroup(of: Bool.self) { group in
        group.addTask { for await _ in engine.events {}; return true }
        group.addTask { try? await Task.sleep(for: .seconds(10)); return false }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    #expect(ended)
}

@Test @MainActor func apagarDuranteElArranqueNoDejaLaFuenteViva() async throws {
    let source = FakeAudioSource()
    source.holdStart = true
    let engine = englishEngine(source)
    let starting = Task { try await engine.start() }

    // Espera a que el arranque llegue a la fuente.
    for _ in 0 ..< 500 where source.gate == nil {
        try await Task.sleep(for: .milliseconds(20))
    }
    try #require(source.gate != nil)

    starting.cancel()
    source.gate?.resume()
    await #expect(throws: CancellationError.self) { try await starting.value }
    #expect(source.stopCalls == 1)
    #expect(engine.phase != .ready)
}
