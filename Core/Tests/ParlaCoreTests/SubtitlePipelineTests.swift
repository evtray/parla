import Testing
import Foundation
@testable import ParlaCore

private struct PrefixTranslator: Translator {
    func translate(_ text: String) async throws -> String { "ES:" + text }
}

private struct FailingTranslator: Translator {
    struct Down: Error {}
    func translate(_ text: String) async throws -> String { throw Down() }
}

private let t0 = Date(timeIntervalSince1970: 1000)

private func collect(_ pipeline: SubtitlePipeline) async -> [SubtitleOutput] {
    var all: [SubtitleOutput] = []
    for await output in pipeline.outputs { all.append(output) }
    return all
}

@Test func traduceYGuardaLaFraseCerrada() async {
    let transcriber = FakeTranscriber(script: [
        (.partial("hello"), t0),
        (.final("hello world"), t0.addingTimeInterval(1)),
    ])
    let outputs = await collect(SubtitlePipeline(transcriber: transcriber,
                                                 translator: PrefixTranslator(),
                                                 tickInterval: nil))
    #expect(outputs.contains(.line(SubtitleLine(english: "hello world",
                                                spanish: "ES:hello world", spokenAt: t0))))
    let lastShown = outputs.compactMap { if case .show(let frame) = $0 { frame } else { nil } }.last
    #expect(lastShown?.current == "ES:hello world")
}

@Test func conElTraductorCaidoGuardaLaFraseSinTraducir() async {
    let transcriber = FakeTranscriber(script: [(.final("break a leg"), t0)])
    let outputs = await collect(SubtitlePipeline(transcriber: transcriber,
                                                 translator: FailingTranslator(),
                                                 tickInterval: nil))
    #expect(outputs.contains(.line(SubtitleLine(english: "break a leg",
                                                spanish: "", spokenAt: t0))))
}
