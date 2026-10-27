import Testing
import Foundation
import CoreGraphics
import SwiftData
import ParlaCore
@testable import Parla

// MARK: - Fakes

private let pixel: CGImage = {
    let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}()

/// Los fotogramas los manda el test, uno a uno.
private final class FakeFrameSource: FrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<LiveFrameEvent>.Continuation?
    private var calls = 0

    var framesCalls: Int { lock.withLock { calls } }

    func frames() -> AsyncStream<LiveFrameEvent> {
        let (stream, continuation) = AsyncStream<LiveFrameEvent>.makeStream()
        lock.withLock {
            calls += 1
            self.continuation = continuation
        }
        return stream
    }

    func snapshot() async throws -> CGImage { pixel }

    func send(_ event: LiveFrameEvent) {
        _ = lock.withLock { continuation }?.yield(event)
    }
}

/// Lo que «lee» Vision, en orden: cada lectura toma el siguiente texto.
private final class TextScript: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String]
    private var readsDone = 0
    var failure: (any Error)?

    init(_ texts: [String] = []) { self.texts = texts }

    var reads: Int { lock.withLock { readsDone } }

    func add(_ more: [String]) { lock.withLock { texts += more } }

    func read(_ image: CGImage) async throws -> String {
        try lock.withLock {
            readsDone += 1
            if let failure { throw failure }
            return texts.isEmpty ? "" : texts.removeFirst()
        }
    }
}

/// Traduce «X» como «es: X». Con la puerta cerrada, retiene las respuestas
/// hasta `open()`.
private actor FakeLiveTranslator: LiveReadingTranslator {
    private(set) var calls: [[String]] = []
    private(set) var explained: [String] = []
    private var closed = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var failures: [String: ExplainerError] = [:]

    func close() { closed = true }

    func open() {
        closed = false
        waiting.forEach { $0.resume() }
        waiting = []
    }

    func fail(_ line: String, with error: ExplainerError?) { failures[line] = error }

    func translate(_ lines: [String], context: NotebookContext) async throws -> [LiveTranslation?] {
        calls.append(lines)
        if closed { await withCheckedContinuation { waiting.append($0) } }
        if let error = lines.compactMap({ failures[$0] }).first { throw error }
        return lines.map { LiveTranslation(spanish: "es: \($0)", save: false, expressions: []) }
    }

    func explain(_ line: String, context: NotebookContext) async throws -> LiveTranslation? {
        explained.append(line)
        return LiveTranslation(spanish: "es: \(line)", save: true,
                               expressions: [LiveExpression(phrase: line, meaning: "algo")])
    }
}

// MARK: - Ayudantes

@MainActor
private func makeSession(rhythm: LiveRhythm = .automatic, script: TextScript,
                         translator: FakeLiveTranslator, frames: FakeFrameSource)
    throws -> (LiveSession, ModelContainer) {
    let container = try Persistence.makeContainer(ModelConfiguration(isStoredInMemoryOnly: true))
    let session = LiveSession(
        setup: LiveSetup(source: .screen, region: CGRect(x: 0, y: 0, width: 10, height: 10),
                         notebookID: nil),
        rhythm: rhythm, frames: frames, read: { try await script.read($0) },
        translator: translator, store: NotebookStore(modelContainer: container))
    return (session, container)
}

/// Espera a que se cumpla la condición, como mucho 2 s.
@MainActor
private func until(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("la condición no se cumplió a tiempo")
}

/// Cada texto se lee dos veces para que el detector lo dé por asentado.
private func twice(_ texts: [String]) -> [String] { texts.flatMap { [$0, $0] } }

@MainActor
private func feed(_ frames: FakeFrameSource, _ script: TextScript, _ count: Int) async {
    let before = script.reads
    for _ in 0..<count { frames.send(.frame(pixel)) }
    await until { script.reads == before + count }
}

// MARK: - Tests

@MainActor @Test func unaLineaNuevaSeTraduceYSeGuarda() async throws {
    let frames = FakeFrameSource(), script = TextScript(twice(["Hold the line."]))
    let (session, container) = try makeSession(script: script, translator: FakeLiveTranslator(),
                                               frames: frames)
    session.start()
    await feed(frames, script, 2)
    await until { session.lines.first?.status == .translated(
        LiveTranslation(spanish: "es: Hold the line.", save: false, expressions: [])) }
    let stored = try ModelContext(container).fetch(FetchDescriptor<NotebookLine>())
    #expect(stored.map(\.english) == ["Hold the line."])
    await until { (try? ModelContext(container).fetch(FetchDescriptor<NotebookLine>()))?
        .first?.spanish == "es: Hold the line." }
}

@MainActor @Test func lasPendientesVanJuntasEnOrden() async throws {
    let frames = FakeFrameSource(), script = TextScript(twice(["A.", "B.", "C."]))
    let translator = FakeLiveTranslator()
    await translator.close()
    let (session, _) = try makeSession(script: script, translator: translator, frames: frames)
    session.start()
    await feed(frames, script, 6)
    await until { session.lines.count == 3 }
    await translator.open()
    await until { await translator.calls.count == 2 }
    #expect(await translator.calls == [["A."], ["B.", "C."]])
}

@MainActor @Test func masDeCincoPendientesVanEnTandasDeCinco() async throws {
    let texts = (1...8).map { "Line \($0)." }
    let frames = FakeFrameSource(), script = TextScript(twice(texts))
    let translator = FakeLiveTranslator()
    await translator.close()
    let (session, _) = try makeSession(script: script, translator: translator, frames: frames)
    session.start()
    await feed(frames, script, 16)
    await until { session.lines.count == 8 }
    await translator.open()
    await until { await translator.calls.count == 3 }
    #expect(await translator.calls == [[texts[0]], Array(texts[1...5]), Array(texts[6...7])])
}

@MainActor @Test func unErrorDejaLaLineaSinTraducirYSePuedeReintentar() async throws {
    let frames = FakeFrameSource(), script = TextScript(twice(["A."]))
    let translator = FakeLiveTranslator()
    await translator.fail("A.", with: .network("sin red"))
    let (session, _) = try makeSession(script: script, translator: translator, frames: frames)
    session.start()
    await feed(frames, script, 2)
    await until { session.lines.first?.status == .untranslated("Sin conexión") }
    await translator.fail("A.", with: nil)
    session.retry(try #require(session.lines.first?.id))
    await until { if case .translated = session.lines.first?.status { true } else { false } }
    #expect(await translator.calls == [["A."], ["A."]])
}

@MainActor @Test func sinClaveLaLineaQuedaSinTraducirYLaLecturaSigue() async throws {
    let frames = FakeFrameSource(), script = TextScript(twice(["A.", "B."]))
    let translator = FakeLiveTranslator()
    await translator.fail("A.", with: .missingAPIKey)
    let (session, _) = try makeSession(script: script, translator: translator, frames: frames)
    session.start()
    await feed(frames, script, 2)
    await until { session.lines.first?.status == .untranslated("Falta la clave de API") }
    await feed(frames, script, 2)
    await until { session.lines.count == 2 }
    await until { if case .translated = session.lines.first?.status { true } else { false } }
    #expect(session.state == .running)
}

@MainActor @Test func noVuelveATraducirSuPropiaTraduccion() async throws {
    let frames = FakeFrameSource(), script = TextScript(twice(["A."]))
    let (session, _) = try makeSession(script: script, translator: FakeLiveTranslator(),
                                       frames: frames)
    session.start()
    await feed(frames, script, 2)
    await until { if case .translated = session.lines.first?.status { true } else { false } }
    script.add(twice(["es: A."]))
    await feed(frames, script, 2)
    #expect(session.lines.count == 1)
}

@MainActor @Test func laPausaDetieneLaLectura() async throws {
    let frames = FakeFrameSource(), script = TextScript()
    let (session, _) = try makeSession(script: script, translator: FakeLiveTranslator(),
                                       frames: frames)
    session.start()
    await until { frames.framesCalls == 1 }
    frames.send(.paused(.windowClosed))
    await until { session.state == .paused(.windowClosed) }
    frames.send(.frame(pixel))
    frames.send(.resumed)
    await until { session.state == .running }
    #expect(script.reads == 0)
}

@MainActor @Test func leerAhoraConElRecuadroVacioAvisa() async throws {
    let (session, _) = try makeSession(rhythm: .onDemand, script: TextScript([""]),
                                       translator: FakeLiveTranslator(), frames: FakeFrameSource())
    session.start()
    await session.readNow()
    #expect(session.notice == "No encontré texto en el recuadro")
    #expect(session.lines.isEmpty)
}

@MainActor @Test func leerAhoraTraduceAunqueSeRepita() async throws {
    let script = TextScript(["A.", "A."])
    let (session, _) = try makeSession(rhythm: .onDemand, script: script,
                                       translator: FakeLiveTranslator(), frames: FakeFrameSource())
    session.start()
    await session.readNow()
    await session.readNow()
    #expect(session.lines.map(\.english) == ["A.", "A."])
    #expect(session.notice == nil)
}

@MainActor @Test func enCuandoYoDigaNoSeConsumenFotogramas() async throws {
    let frames = FakeFrameSource()
    let (session, _) = try makeSession(rhythm: .onDemand, script: TextScript(),
                                       translator: FakeLiveTranslator(), frames: frames)
    session.start()
    try await Task.sleep(for: .milliseconds(50))
    #expect(frames.framesCalls == 0)
    session.rhythm = .automatic
    await until { frames.framesCalls == 1 }
}

@MainActor @Test func guardarAManoSinExpresionesPideExplicar() async throws {
    let frames = FakeFrameSource(), script = TextScript(twice(["Piece of cake."]))
    let translator = FakeLiveTranslator()
    let (session, container) = try makeSession(script: script, translator: translator,
                                               frames: frames)
    session.start()
    await feed(frames, script, 2)
    await until { if case .translated = session.lines.first?.status { true } else { false } }
    session.save(try #require(session.lines.first?.id))
    await until { session.lines.first?.isSaved == true }
    #expect(await translator.explained == ["Piece of cake."])
    await until { (try? ModelContext(container).fetch(FetchDescriptor<NotebookLine>()))?
        .first?.isSaved == true }
}

@MainActor @Test func unFalloDelLectorPausaLaSesion() async throws {
    struct VisionFailed: Error {}
    let frames = FakeFrameSource(), script = TextScript()
    script.failure = VisionFailed()
    let (session, _) = try makeSession(script: script, translator: FakeLiveTranslator(),
                                       frames: frames)
    session.start()
    await until { frames.framesCalls == 1 }
    frames.send(.frame(pixel))
    await until { if case .paused(.readerFailed) = session.state { true } else { false } }
}
