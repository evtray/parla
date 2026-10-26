import ParlaCore

/// En qué lado de la tarjeta está el inglés: es lo que va en serif y lo que se
/// copia. No siempre es el mismo campo: depende del modo y del caso.
enum EnglishSide: Equatable {
    case source, result, both

    init(origin: String, kind: String?) {
        switch origin {
        case "system":
            self = .source
        case "screen":
            switch kind.flatMap(CaptureKind.init(rawValue:)) {
            case .translate: self = .result
            case .correct: self = .both
            default: self = .source    // entender, o una fila sin caso
            }
        default:
            self = .result             // voz: dices en español, sale en inglés
        }
    }

    var sourceIsEnglish: Bool { self != .result }
    var resultIsEnglish: Bool { self != .source }
}

extension StoredCard {
    var englishSide: EnglishSide { EnglishSide(origin: origin, kind: kind) }

    /// Lo que copia «Copiar el inglés». En una corrección, la versión corregida.
    var englishText: String { englishSide == .source ? source : result }

    /// El otro lado: el español, o el borrador en una corrección.
    var otherText: String { englishSide == .source ? result : source }
}

/// El icono y el nombre de cada origen en el historial. Sustituyen al emoji.
enum CardOriginStyle {
    static func symbol(origin: String) -> String {
        switch origin {
        case "screen": "crop"
        case "system": "captions.bubble"
        default: "mic"
        }
    }

    static func name(origin: String, kind: String?) -> String {
        switch origin {
        case "screen": kind.flatMap(CaptureKind.init(rawValue:))?.title ?? "Captura"
        case "system": "Subtítulos"
        default: "Voz"
        }
    }
}

extension CaptureCard {
    /// Lo que lee «Escuchar»: el mismo lado que copia el historial.
    var englishText: String {
        EnglishSide(origin: "screen", kind: kind.rawValue) == .source ? source : result
    }
}
