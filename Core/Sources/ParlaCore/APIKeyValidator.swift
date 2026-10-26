import Foundation

public enum KeyCheck: Sendable, Equatable {
    case valid
    /// La API la rechazó (401 o 403).
    case invalid
    /// No se pudo saber: sin red, tiempo agotado u otro error del servidor.
    case unverified

    /// Se guarda salvo que la API la haya rechazado: perder una clave buena
    /// por un wifi caído sería peor que guardar una sin comprobar.
    public var shouldSave: Bool { self != .invalid }
}

/// Comprueba una clave antes de guardarla, para que una clave mala se note al
/// escribirla y no en la primera traducción.
public struct APIKeyValidator: Sendable {
    private let streamer: any HTTPStreamer

    public init(streamer: any HTTPStreamer = URLSessionStreamer()) {
        self.streamer = streamer
    }

    /// Al pegar es fácil arrastrar un espacio o un salto de línea.
    public static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func check(_ key: String) async -> KeyCheck {
        let key = Self.normalize(key)
        guard !key.isEmpty else { return .invalid }
        do {
            let response = try await streamer.stream(ClaudeRequestBuilder.makeModelsRequest(apiKey: key))
            switch response.statusCode {
            case 200: return .valid
            case 401, 403: return .invalid
            default: return .unverified
            }
        } catch {
            return .unverified
        }
    }
}
