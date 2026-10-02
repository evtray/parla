import ParlaCore

extension SetupItem {
    var title: String {
        switch self {
        case .apiKey:          "Falta la clave de Anthropic"
        case .microphone:      "Parla no puede usar el micrófono"
        case .screenRecording: "Falta el permiso de Grabación de pantalla"
        case .languages:       "Falta el inglés en Traducción"
        }
    }

    var symbol: String {
        switch self {
        case .apiKey:          "key"
        case .microphone:      "mic"
        case .screenRecording: "rectangle.dashed"
        case .languages:       "globe"
        }
    }
}

extension SetupFix {
    /// `nil` cuando no hay nada que pulsar.
    var buttonTitle: String? {
        switch self {
        case .enterAPIKey: "Añadir clave"
        case .requestMicrophone, .requestScreenRecording: "Permitir"
        case .openMicrophoneSettings, .openScreenRecordingSettingsOrRelaunch: "Abrir Ajustes del Sistema"
        case .openLanguageSettings: "Abrir Idioma y región"
        case .unavailable: nil
        }
    }
}

extension SetupIssue {
    var reason: String {
        switch (item, fix) {
        case (.apiKey, _):
            "La voz y las capturas usan Claude. La clave se guarda en el Llavero."
        case (.microphone, .requestMicrophone):
            "El modo voz lo necesita para oírte."
        case (.microphone, _):
            "Lo denegaste antes. Actívalo para Parla en Ajustes del Sistema."
        case (.screenRecording, .requestScreenRecording):
            "Las capturas y los subtítulos lo necesitan para ver y oír la pantalla."
        case (.screenRecording, _):
            "Actívalo para Parla en Ajustes del Sistema. Si ya lo hiciste, reabre Parla: "
                + "macOS no lo aplica antes."
        case (.languages, .unavailable):
            "Este Mac no puede traducir del inglés al español."
        case (.languages, _):
            "Los subtítulos se traducen en tu Mac. Añade inglés y español en Idiomas de traducción."
        }
    }
}
