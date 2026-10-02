import Foundation

/// Lo que se ve en la banda en un momento dado.
public struct SubtitleFrame: Sendable, Equatable {
    /// La frase anterior, ya cerrada. Va atenuada encima.
    public let previous: String?
    /// La que se está diciendo.
    public let current: String
    public let currentIsFinal: Bool
    /// `true` si es el inglés porque la traducción falló.
    public let currentIsOriginal: Bool

    public init(previous: String?, current: String,
                currentIsFinal: Bool, currentIsOriginal: Bool) {
        self.previous = previous
        self.current = current
        self.currentIsFinal = currentIsFinal
        self.currentIsOriginal = currentIsOriginal
    }
}

/// Una frase cerrada, para el historial.
public struct SubtitleLine: Sendable, Equatable {
    public let english: String
    /// Vacío si la traducción falló.
    public let spanish: String
    /// Cuándo empezó a decirse.
    public let spokenAt: Date

    public init(english: String, spanish: String, spokenAt: Date) {
        self.english = english
        self.spanish = spanish
        self.spokenAt = spokenAt
    }
}

public enum SubtitleOutput: Sendable, Equatable {
    case show(SubtitleFrame)
    case hide
    case line(SubtitleLine)
}

/// Del inglés al español. Separado para que el pipeline se pruebe sin el
/// framework de traducción, que vive en App.
public protocol Translator: Sendable {
    func translate(_ text: String) async throws -> String
}
