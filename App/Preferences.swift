import Foundation

/// Lo que se elige en Ajustes y sobrevive a cerrar la app.
///
/// `UserDefaults` es seguro entre hilos aunque el SDK no lo declare `Sendable`.
struct Preferences: @unchecked Sendable {
    static let shared = Preferences(defaults: .standard)

    /// Inyectable para que los tests escriban en un almacén propio y no en los
    /// ajustes reales.
    let defaults: UserDefaults

    private enum Key {
        static let translationMode = "translationMode"
        static let model = "model"
        static let inputDeviceUID = "inputDeviceUID"
        static let readsSubtitlesAloud = "readsSubtitlesAloud"
    }

    var translationMode: TranslationMode {
        get {
            defaults.string(forKey: Key.translationMode)
                .flatMap(TranslationMode.init(rawValue:)) ?? .immediate
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.translationMode) }
    }

    /// Un identificador guardado que ya no existe cae al modelo por defecto:
    /// la app nunca se queda sin modelo con el que traducir.
    var model: ClaudeModel {
        get {
            defaults.string(forKey: Key.model)
                .flatMap(ClaudeModel.init(rawValue:)) ?? .default
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.model) }
    }

    /// `nil` es "el micrófono del sistema".
    var inputDeviceUID: String? {
        get { defaults.string(forKey: Key.inputDeviceUID) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Key.inputDeviceUID)
            } else {
                defaults.removeObject(forKey: Key.inputDeviceUID)
            }
        }
    }

    /// Leer en voz alta las frases traducidas de los subtítulos. Encendido si
    /// nunca se tocó.
    var readsSubtitlesAloud: Bool {
        get { defaults.object(forKey: Key.readsSubtitlesAloud) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.readsSubtitlesAloud) }
    }
}
