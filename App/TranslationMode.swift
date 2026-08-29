import Foundation

/// Cuándo se le pide la explicación al modelo.
enum TranslationMode: String, CaseIterable, Sendable, Identifiable {
    /// Una petición por frase, en cuanto dejas de hablar.
    case immediate
    /// Las frases se guardan y se mandan todas juntas cuando tú lo pides.
    case batch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .immediate: "Traducir cada frase al vuelo"
        case .batch:     "Acumular y traducir cuando yo lo pida"
        }
    }

    var detail: String {
        switch self {
        case .immediate:
            "La tarjeta sale unos segundos después de cada frase. Una petición por frase."
        case .batch:
            "No se manda nada hasta que pulsas «Traducir». Gasta menos y, como el "
            + "modelo ve la sesión entera de una vez, añade un resumen de lo que repites."
        }
    }
}

enum Preferences {
    private static let translationModeKey = "translationMode"

    static var translationMode: TranslationMode {
        get {
            UserDefaults.standard.string(forKey: translationModeKey)
                .flatMap(TranslationMode.init(rawValue:)) ?? .immediate
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: translationModeKey) }
    }
}
