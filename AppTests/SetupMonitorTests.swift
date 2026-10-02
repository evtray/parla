import Testing
import Foundation
import AVFoundation
import ParlaCore
@testable import Parla

@MainActor
private final class FakeSources: SetupSources {
    var hasAPIKey = true
    var microphone: PermissionState = .granted
    var screenRecordingGranted = true
    var languageAnswer: LanguageState = .ready
    private(set) var calls: [String] = []

    func languages() async -> LanguageState { languageAnswer }
    func requestMicrophone() async { calls.append("requestMicrophone"); microphone = .granted }
    func requestScreenRecording() { calls.append("requestScreenRecording") }
    func open(_ pane: SystemSettingsPane) { calls.append("open \(pane)") }
    func relaunch() { calls.append("relaunch") }
}

/// Un almacén propio por test: los ajustes reales de Parla no se tocan.
private func scratchPreferences() -> (Preferences, () -> Void) {
    let name = "parla-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (Preferences(defaults: defaults), { defaults.removePersistentDomain(forName: name) })
}

@Test @MainActor func losIdiomasNoSeSabenHastaPreguntar() async {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.languageAnswer = .needsDownload
    let monitor = SetupMonitor(sources: sources, preferences: preferences)
    #expect(monitor.status.isComplete)
    await monitor.refresh()
    #expect(monitor.status.issues.map(\.item) == [.languages])
}

@Test @MainActor func refrescarRecogeLoQueCambioFuera() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    let monitor = SetupMonitor(sources: sources, preferences: preferences)
    sources.hasAPIKey = false
    monitor.refreshNow()
    #expect(monitor.status.issues.map(\.item) == [.apiKey])
}

@Test @MainActor func pedirLaPantallaQuedaApuntadoParaLaProximaVez() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.screenRecordingGranted = false
    let monitor = SetupMonitor(sources: sources, preferences: preferences)
    #expect(monitor.status.issues.first?.fix == .requestScreenRecording)

    monitor.requestScreenRecording()

    #expect(sources.calls == ["requestScreenRecording"])
    #expect(monitor.status.issues.first?.fix == .openScreenRecordingSettingsOrRelaunch)
    // Al reabrir Parla se sigue sabiendo.
    let reopened = SetupMonitor(sources: sources, preferences: preferences)
    #expect(reopened.status.issues.first?.fix == .openScreenRecordingSettingsOrRelaunch)
}

@Test @MainActor func unaPantallaDenegadaPorPrimeraVezLanzaElDialogo() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.screenRecordingGranted = false
    SetupMonitor(sources: sources, preferences: preferences).screenRecordingWasDenied()
    #expect(sources.calls == ["requestScreenRecording"])
    #expect(preferences.screenRecordingRequested)
}

@Test @MainActor func unaPantallaDenegadaOtraVezNoRepiteElDialogo() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    preferences.screenRecordingRequested = true
    let sources = FakeSources()
    sources.screenRecordingGranted = false
    SetupMonitor(sources: sources, preferences: preferences).screenRecordingWasDenied()
    #expect(sources.calls.isEmpty)
}

@Test @MainActor func cadaArregloLlamaALoQueToca() async {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.microphone = .notDetermined
    let monitor = SetupMonitor(sources: sources, preferences: preferences)

    await monitor.perform(.requestMicrophone)
    await monitor.perform(.openMicrophoneSettings)
    await monitor.perform(.openScreenRecordingSettingsOrRelaunch)
    await monitor.perform(.openLanguageSettings)
    await monitor.perform(.unavailable)

    #expect(sources.calls == ["requestMicrophone", "open microphone",
                              "open screenRecording", "open languages"])
    #expect(monitor.status.isComplete)
}

@Test func losPermisosDelSistemaSeTraducenBien() {
    #expect(PermissionState(AVAuthorizationStatus.authorized) == .granted)
    #expect(PermissionState(AVAuthorizationStatus.notDetermined) == .notDetermined)
    #expect(PermissionState(AVAuthorizationStatus.denied) == .denied)
    // Restringido no se puede pedir: «Permitir» no haría nada.
    #expect(PermissionState(AVAuthorizationStatus.restricted) == .denied)
}

@Test func laDisponibilidadDeIdiomasSeTraduceBien() {
    #expect(LanguageState(LiveTranslator.Readiness.ready) == .ready)
    #expect(LanguageState(LiveTranslator.Readiness.needsLanguages) == .needsDownload)
    #expect(LanguageState(LiveTranslator.Readiness.unsupported) == .unsupported)
}

@Test func cadaPendienteTieneTituloMotivoEIcono() {
    let issues = [
        SetupIssue(item: .apiKey, fix: .enterAPIKey),
        SetupIssue(item: .microphone, fix: .requestMicrophone),
        SetupIssue(item: .microphone, fix: .openMicrophoneSettings),
        SetupIssue(item: .screenRecording, fix: .requestScreenRecording),
        SetupIssue(item: .screenRecording, fix: .openScreenRecordingSettingsOrRelaunch),
        SetupIssue(item: .languages, fix: .openLanguageSettings),
        SetupIssue(item: .languages, fix: .unavailable),
    ]
    for issue in issues {
        #expect(!issue.item.title.isEmpty)
        #expect(!issue.item.symbol.isEmpty)
        #expect(!issue.reason.isEmpty)
    }
    // Pedir y denegar no se explican igual.
    #expect(issues[1].reason != issues[2].reason)
}

@Test func soloLoQueNoTieneArregloVaSinBoton() {
    #expect(SetupFix.unavailable.buttonTitle == nil)
    for fix: SetupFix in [.enterAPIKey, .requestMicrophone, .openMicrophoneSettings,
                          .requestScreenRecording, .openScreenRecordingSettingsOrRelaunch,
                          .openLanguageSettings] {
        #expect(fix.buttonTitle != nil)
    }
}
