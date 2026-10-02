import Foundation

/// Una región de la pantalla, ya reducida a lo que el modelo aprovecha.
public struct Capture: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let imageData: Data
    /// `"image/png"` casi siempre; `"image/jpeg"` si el PNG no cabía.
    public let mediaType: String
    /// Ordena la tarjeta en el panel junto a las de voz.
    public let capturedAt: Date

    public init(id: UUID = UUID(), imageData: Data, mediaType: String, capturedAt: Date) {
        self.id = id
        self.imageData = imageData
        self.mediaType = mediaType
        self.capturedAt = capturedAt
    }
}

/// Qué hace la tarjeta con el texto de la captura. El orden es el del `enum`
/// del esquema de salida.
public enum CaptureKind: String, Sendable, Codable, CaseIterable {
    /// Inglés de otra persona: qué significa y qué tiene de no evidente.
    case understand
    /// Inglés escrito por el usuario: la versión corregida y por qué.
    case correct
    /// Español: cómo se dice en inglés y por qué, como la voz.
    case translate
    /// No había texto que procesar.
    case skip
}

/// Lo que Claude devuelve para una captura. La forma coincide con el
/// `json_schema` de `makeCaptureRequest`, así que se decodifica directo.
public struct CaptureCard: Sendable, Equatable, Codable {
    public let kind: CaptureKind
    /// El texto leído en la imagen, sin la interfaz que lo rodea.
    public let source: String
    /// La traducción, la corrección o el inglés. Siempre completo.
    public let result: String
    public let why: [String]
    public let vocab: [VocabTerm]

    /// En el JSON la respuesta se llama `target`. El cuerpo sale con las claves
    /// en orden alfabético y el modelo escribe en el orden del esquema: así lee
    /// (`source`) antes de responder (`target`).
    enum CodingKeys: String, CodingKey {
        case kind, source, result = "target", why, vocab
    }

    public init(kind: CaptureKind, source: String, result: String,
                why: [String], vocab: [VocabTerm]) {
        self.kind = kind
        self.source = source
        self.result = result
        self.why = why
        self.vocab = vocab
    }
}

/// Separado de `Explainer` para que los dobles del pipeline de voz no tengan
/// que implementar algo que no usan.
public protocol CaptureExplainer: Sendable {
    /// Con `forcing == nil` el modelo decide el caso. Nunca devuelve `nil`: un
    /// `skip` vuelve como tarjeta, porque capturar es un gesto explícito y
    /// merece respuesta.
    func explainCapture(_ capture: Capture,
                        forcing kind: CaptureKind?) async throws -> CaptureCard
}
