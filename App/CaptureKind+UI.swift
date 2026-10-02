import ParlaCore

extension CaptureKind {
    /// La etiqueta de la tarjeta y del historial.
    var label: String {
        switch self {
        case .understand: "📷 Para entender"
        case .correct:    "📷 Corrección"
        case .translate:  "📷 Traducción"
        case .skip:       "📷 Sin texto"
        }
    }

    /// El nombre del caso, sin icono: el historial pone el suyo.
    var title: String {
        switch self {
        case .understand: "Para entender"
        case .correct:    "Corrección"
        case .translate:  "Traducción"
        case .skip:       "Sin texto"
        }
    }

    /// Lo que ofrece «¿No era eso?». `skip` no se ofrece nunca.
    var menuLabel: String {
        switch self {
        case .understand: "No lo escribí yo: explícamelo"
        case .correct:    "Lo escribí yo: corrígelo"
        case .translate:  "Tradúcelo al inglés"
        case .skip:       ""
        }
    }
}
