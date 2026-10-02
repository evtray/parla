import Foundation

/// Qué se lee en voz alta, para ir al día con el video.
///
/// Mientras suena una frase espera como mucho una: la más reciente. Si llega
/// otra, la que esperaba se salta. Así la voz nunca va más de una frase por
/// detrás; lo que se salta sigue en la banda y en el historial.
public struct SpeechQueue: Sendable, Equatable {
    public private(set) var speaking: String?
    public private(set) var waiting: String?

    public init() {}

    /// Devuelve el texto a leer ya, si no sonaba nada.
    public mutating func enqueue(_ text: String) -> String? {
        guard speaking != nil else {
            speaking = text
            return text
        }
        waiting = text
        return nil
    }

    /// La frase en curso terminó. Devuelve la siguiente, si hay.
    public mutating func finished() -> String? {
        speaking = waiting
        waiting = nil
        return speaking
    }
}
