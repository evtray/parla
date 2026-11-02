import ParlaCore

/// Los modelos entre los que se puede elegir.
///
/// Solo están los que aceptan la petición tal como Parla la manda: `effort`,
/// salida estructurada y `fallbacks: "default"`. Haiku es la excepción: no
/// tiene fallback de servidor y `ClaudeRequestBuilder` lo omite para él.
enum ClaudeModel: String, CaseIterable, Sendable, Identifiable {
    case haiku55 = "claude-haiku-5-5"
    case sonnet55 = "claude-sonnet-5-5"
    case opus55 = "claude-opus-5-5"
    case opus5 = "claude-opus-5"
    case fable51 = "claude-fable-5-1"

    static let `default`: ClaudeModel = .opus55

    var id: String { rawValue }

    var label: String {
        switch self {
        case .haiku55:  "Haiku 5.5"
        case .sonnet55: "Sonnet 5.5"
        case .opus55:   "Opus 5.5"
        case .opus5:    "Opus 5"
        case .fable51:  "Fable 5.1"
        }
    }

    /// Los precios son por millón de tokens, entrada / salida.
    var detail: String {
        switch self {
        case .haiku55:  "El más rápido y barato: $0,10 / $0,50 por millón de tokens."
        case .sonnet55: "Rápido y barato: $2 / $10 por millón de tokens."
        case .opus55:   "El equilibrio entre calidad y precio: $4 / $20 por millón de tokens."
        case .opus5:    "El Opus anterior: $5 / $25 por millón de tokens."
        case .fable51:  "El más capaz y el más caro: $10 / $50 por millón de tokens."
        }
    }

    var requestBuilder: ClaudeRequestBuilder { ClaudeRequestBuilder(model: rawValue) }
}
