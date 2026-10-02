import AppKit
import Observation
import ParlaCore

/// Traduce el sistema a `SetupStatus` y ejecuta los arreglos. Es el único sitio
/// que pregunta por la clave, los permisos y los idiomas para saber qué falta.
@MainActor
@Observable
final class SetupMonitor {
    private(set) var status: SetupStatus

    @ObservationIgnored private let sources: any SetupSources
    @ObservationIgnored private let preferences: Preferences
    /// La única respuesta asíncrona. Hasta que llega, no se alarma.
    @ObservationIgnored private var languages: LanguageState = .unknown
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(sources: any SetupSources, preferences: Preferences = .shared) {
        self.sources = sources
        self.preferences = preferences
        status = SetupStatus(Self.inputs(sources, preferences, languages: .unknown))
    }

    private static func inputs(_ sources: any SetupSources, _ preferences: Preferences,
                               languages: LanguageState) -> SetupInputs {
        SetupInputs(hasAPIKey: sources.hasAPIKey,
                    microphone: sources.microphone,
                    screenRecordingGranted: sources.screenRecordingGranted,
                    screenRecordingRequested: preferences.screenRecordingRequested,
                    languages: languages)
    }

    /// Lo que se sabe sin esperar: la clave y los permisos.
    func refreshNow() {
        status = SetupStatus(Self.inputs(sources, preferences, languages: languages))
    }

    /// Además pregunta por los idiomas, que tarda.
    func refresh() async {
        refreshNow()
        languages = await sources.languages()
        refreshNow()
    }

    func perform(_ fix: SetupFix) async {
        switch fix {
        case .enterAPIKey, .unavailable: break
        case .requestMicrophone: await sources.requestMicrophone()
        case .openMicrophoneSettings: sources.open(.microphone)
        case .requestScreenRecording: requestScreenRecording()
        case .openScreenRecordingSettingsOrRelaunch: sources.open(.screenRecording)
        case .openLanguageSettings: sources.open(.languages)
        }
        await refresh()
    }

    /// El diálogo del sistema sale una vez por identidad de app: se apunta para
    /// ofrecer Ajustes del Sistema las siguientes veces.
    func requestScreenRecording() {
        preferences.screenRecordingRequested = true
        sources.requestScreenRecording()
        refreshNow()
    }

    /// La captura o los subtítulos se encontraron sin permiso: la primera vez se
    /// lanza el diálogo; las demás, pedirlo no haría nada.
    func screenRecordingWasDenied() {
        if preferences.screenRecordingRequested {
            refreshNow()
        } else {
            requestScreenRecording()
        }
    }

    func relaunch() {
        sources.relaunch()
    }

    /// Al volver de Ajustes del Sistema, el aviso desaparece solo.
    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }
}
