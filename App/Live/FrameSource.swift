import CoreGraphics

enum LivePauseReason: Equatable, Sendable {
    /// La ventana está minimizada o en otro escritorio: no llegan fotogramas.
    case windowHidden
    case windowClosed
    /// macOS no entrega la ventana mientras está a pantalla completa.
    case fullScreenUnavailable
    /// Vision falló al leer; el texto es el error.
    case readerFailed(String)
}

enum LiveFrameEvent: Sendable {
    case frame(CGImage)
    case paused(LivePauseReason)
    case resumed
}

protocol FrameSource: Sendable {
    /// Fotogramas ya recortados al recuadro, a 2 fps.
    func frames() -> AsyncStream<LiveFrameEvent>
    /// Una sola imagen recortada, para «Leer ahora» y el ritmo «Cuando yo diga».
    func snapshot() async throws -> CGImage
}
