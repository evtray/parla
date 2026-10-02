import AppKit
import AVFoundation
import CoreGraphics
import ParlaCore

/// Lo que `SetupMonitor` pregunta y pide al sistema. Un protocolo para poder
/// probar el monitor sin tocar permisos reales.
@MainActor
protocol SetupSources {
    var hasAPIKey: Bool { get }
    var microphone: PermissionState { get }
    var screenRecordingGranted: Bool { get }
    func languages() async -> LanguageState
    func requestMicrophone() async
    func requestScreenRecording()
    func open(_ pane: SystemSettingsPane)
    func relaunch()
}

/// Los paneles de Ajustes del Sistema que arreglan algo, abiertos directamente.
enum SystemSettingsPane: Sendable {
    case microphone, screenRecording, languages

    var url: URL {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .languages:
            URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
        }
    }
}

extension PermissionState {
    /// «Restringido» (control parental, gestión del Mac) no se puede pedir:
    /// cuenta como denegado, que lleva a Ajustes del Sistema.
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied
        }
    }
}

extension LanguageState {
    init(_ readiness: LiveTranslator.Readiness) {
        switch readiness {
        case .ready: self = .ready
        case .needsLanguages: self = .needsDownload
        case .unsupported: self = .unsupported
        }
    }
}

@MainActor
struct LiveSetupSources: SetupSources {
    var hasAPIKey: Bool { KeychainStore.shared.hasAPIKey }

    var microphone: PermissionState {
        PermissionState(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    func languages() async -> LanguageState {
        LanguageState(await LiveTranslator.readiness())
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    func open(_ pane: SystemSettingsPane) {
        NSWorkspace.shared.open(pane.url)
    }

    /// macOS no aplica el permiso de Grabación de pantalla hasta que la app se
    /// reabre: se abre una instancia nueva y esta termina.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Log.pipeline.error("no se pudo reabrir Parla: \(error.localizedDescription)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
