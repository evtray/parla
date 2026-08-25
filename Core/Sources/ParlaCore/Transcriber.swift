import Foundation

public protocol Transcriber: Sendable {
    /// Eventos de transcripción con la hora en que ocurrieron.
    /// El pipeline necesita la hora para segmentar; el transcriptor la sabe.
    var events: AsyncStream<(TranscriptEvent, Date)> { get }
    func start() async throws
    func stop() async
}
