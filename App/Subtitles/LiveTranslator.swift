import Foundation
import ParlaCore
import Translation

/// Inglés → español con la traducción de Apple, en el Mac y sin coste.
/// `.lowLatency` prioriza la velocidad: el subtítulo tiene que llegar mientras
/// se habla.
/// Clase y no `actor`: `TranslationSession` no es `Sendable` y el actor no
/// puede pasársela a su propio método asíncrono. La sesión solo se toca desde
/// `translate`, de una llamada en una (`SerialGate`).
final class LiveTranslator: Translator, @unchecked Sendable {

    enum Readiness: Equatable, Sendable {
        case ready
        /// Soportados pero sin descargar.
        case needsLanguages
        case unsupported
    }

    private static let english = Locale.Language(identifier: "en")
    private static let spanish = Locale.Language(identifier: "es")

    private let session = TranslationSession(installedSource: LiveTranslator.english,
                                             target: LiveTranslator.spanish,
                                             preferredStrategy: .lowLatency)

    /// El pipeline pide traducciones solapadas (un parcial y su final casi a la
    /// vez), y `TranslationSession` no promete ser segura entre hilos: van de una
    /// en una. Las respuestas viejas ya se descartan por número de orden.
    private let gate = SerialGate()

    func translate(_ text: String) async throws -> String {
        try await gate.run { try await self.session.translate(text).targetText }
    }

    static func readiness() async -> Readiness {
        switch await LanguageAvailability().status(from: english, to: spanish) {
        case .installed: .ready
        case .supported: .needsLanguages
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }

    nonisolated static func notice(for readiness: Readiness) -> String? {
        switch readiness {
        case .ready:
            nil
        case .needsLanguages:
            "Faltan el inglés y el español en Ajustes del Sistema › General › "
                + "Idioma y región › Idiomas de traducción."
        case .unsupported:
            "Este Mac no puede traducir del inglés al español."
        }
    }
}
