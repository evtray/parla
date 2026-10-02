import Foundation

/// Los tres modos de Parla, para preguntar qué necesita cada uno.
public enum ParlaMode: Sendable, CaseIterable, Hashable {
    case voice, capture, subtitles
}

public enum PermissionState: Sendable, Equatable {
    case granted, notDetermined, denied
}

public enum LanguageState: Sendable, Equatable {
    /// Todavía no se ha preguntado: la respuesta es asíncrona.
    case unknown
    case ready, needsDownload, unsupported
}

/// Lo que la app sabe del sistema. Lo rellena `SetupMonitor`; aquí no se toca
/// nada del sistema, para poder probarlo.
public struct SetupInputs: Sendable, Equatable {
    public var hasAPIKey: Bool
    public var microphone: PermissionState
    public var screenRecordingGranted: Bool
    /// Si ya se lanzó alguna vez el diálogo del sistema para la pantalla.
    public var screenRecordingRequested: Bool
    public var languages: LanguageState

    public init(hasAPIKey: Bool, microphone: PermissionState, screenRecordingGranted: Bool,
                screenRecordingRequested: Bool, languages: LanguageState) {
        self.hasAPIKey = hasAPIKey
        self.microphone = microphone
        self.screenRecordingGranted = screenRecordingGranted
        self.screenRecordingRequested = screenRecordingRequested
        self.languages = languages
    }
}

/// Lo que se puede tener pendiente, en el orden en que se enseña.
public enum SetupItem: Sendable, CaseIterable, Hashable {
    case apiKey, microphone, screenRecording, languages

    /// Los modos que no funcionan sin esto.
    var modes: Set<ParlaMode> {
        switch self {
        case .apiKey:          [.voice, .capture]
        case .microphone:      [.voice]
        case .screenRecording: [.capture, .subtitles]
        case .languages:       [.subtitles]
        }
    }
}

public enum SetupFix: Sendable, Equatable {
    case enterAPIKey
    case requestMicrophone
    case openMicrophoneSettings
    case requestScreenRecording
    /// Abrir Ajustes del Sistema y, si ya se concedió, reabrir Parla.
    case openScreenRecordingSettingsOrRelaunch
    case openLanguageSettings
    /// Este Mac no puede: solo se explica.
    case unavailable

    /// Pedir un permiso no impide arrancar: el propio arranque lanza el
    /// diálogo del sistema, que es justo cuando su motivo es evidente.
    public var isPermissionRequest: Bool {
        self == .requestMicrophone || self == .requestScreenRecording
    }
}

public struct SetupIssue: Sendable, Equatable, Identifiable {
    public let item: SetupItem
    public let fix: SetupFix

    public var id: SetupItem { item }

    public init(item: SetupItem, fix: SetupFix) {
        self.item = item
        self.fix = fix
    }
}

/// Qué falta para que cada modo funcione. La única fuente de esa respuesta: la
/// bienvenida, el menú emergente, Estudio y el panel la leen de aquí.
public struct SetupStatus: Sendable, Equatable {
    public let issues: [SetupIssue]

    public init(_ inputs: SetupInputs) {
        var issues: [SetupIssue] = []
        if !inputs.hasAPIKey {
            issues.append(SetupIssue(item: .apiKey, fix: .enterAPIKey))
        }
        switch inputs.microphone {
        case .granted: break
        case .notDetermined: issues.append(SetupIssue(item: .microphone, fix: .requestMicrophone))
        case .denied: issues.append(SetupIssue(item: .microphone, fix: .openMicrophoneSettings))
        }
        if !inputs.screenRecordingGranted {
            issues.append(SetupIssue(item: .screenRecording,
                                     fix: inputs.screenRecordingRequested
                                         ? .openScreenRecordingSettingsOrRelaunch
                                         : .requestScreenRecording))
        }
        switch inputs.languages {
        case .unknown, .ready: break
        case .needsDownload: issues.append(SetupIssue(item: .languages, fix: .openLanguageSettings))
        case .unsupported: issues.append(SetupIssue(item: .languages, fix: .unavailable))
        }
        self.issues = issues
    }

    public var isComplete: Bool { issues.isEmpty }

    /// Todos los pendientes que afectan al modo, para mostrarlos.
    public func blockers(for mode: ParlaMode) -> [SetupIssue] {
        issues.filter { $0.item.modes.contains(mode) }
    }

    /// Los que impiden arrancarlo: `blockers(for:)` sin los de pedir permiso.
    public func startBlockers(for mode: ParlaMode) -> [SetupIssue] {
        blockers(for: mode).filter { !$0.fix.isPermissionRequest }
    }
}
