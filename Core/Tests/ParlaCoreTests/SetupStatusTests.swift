import Testing
@testable import ParlaCore

private func inputs(hasAPIKey: Bool = true,
                    microphone: PermissionState = .granted,
                    screen: Bool = true,
                    requested: Bool = false,
                    languages: LanguageState = .ready) -> SetupInputs {
    SetupInputs(hasAPIKey: hasAPIKey, microphone: microphone, screenRecordingGranted: screen,
                screenRecordingRequested: requested, languages: languages)
}

@Test func conTodoListoNoHayPendientes() {
    let status = SetupStatus(inputs())
    #expect(status.issues.isEmpty)
    #expect(status.isComplete)
}

@Test func sinClaveSeOfreceEscribirla() {
    #expect(SetupStatus(inputs(hasAPIKey: false)).issues
            == [SetupIssue(item: .apiKey, fix: .enterAPIKey)])
}

@Test func elMicrofonoSinDecidirSePide() {
    #expect(SetupStatus(inputs(microphone: .notDetermined)).issues
            == [SetupIssue(item: .microphone, fix: .requestMicrophone)])
}

@Test func elMicrofonoDenegadoLlevaAAjustes() {
    #expect(SetupStatus(inputs(microphone: .denied)).issues
            == [SetupIssue(item: .microphone, fix: .openMicrophoneSettings)])
}

@Test func laPantallaNuncaPedidaSePide() {
    #expect(SetupStatus(inputs(screen: false, requested: false)).issues
            == [SetupIssue(item: .screenRecording, fix: .requestScreenRecording)])
}

@Test func laPantallaYaPedidaLlevaAAjustesOAReabrir() {
    // macOS solo enseña su diálogo una vez y no aplica el permiso hasta reabrir.
    #expect(SetupStatus(inputs(screen: false, requested: true)).issues
            == [SetupIssue(item: .screenRecording, fix: .openScreenRecordingSettingsOrRelaunch)])
}

@Test func losIdiomasSinDescargarLlevanAIdiomaYRegion() {
    #expect(SetupStatus(inputs(languages: .needsDownload)).issues
            == [SetupIssue(item: .languages, fix: .openLanguageSettings)])
}

@Test func unMacSinTraduccionSoloLoExplica() {
    #expect(SetupStatus(inputs(languages: .unsupported)).issues
            == [SetupIssue(item: .languages, fix: .unavailable)])
}

@Test func losIdiomasTodaviaSinComprobarNoSonPendientes() {
    // Aún no se sabe: no se alarma.
    #expect(SetupStatus(inputs(languages: .unknown)).isComplete)
}

@Test func losPendientesSalenSiempreEnElMismoOrden() {
    let status = SetupStatus(inputs(hasAPIKey: false, microphone: .denied, screen: false,
                                    languages: .needsDownload))
    #expect(status.issues.map(\.item) == [.apiKey, .microphone, .screenRecording, .languages])
}

@Test func cadaModoVeSoloLoQueNecesita() {
    let status = SetupStatus(inputs(hasAPIKey: false, microphone: .denied, screen: false,
                                    requested: true, languages: .needsDownload))
    #expect(status.blockers(for: .voice).map(\.item) == [.apiKey, .microphone])
    #expect(status.blockers(for: .capture).map(\.item) == [.apiKey, .screenRecording])
    #expect(status.blockers(for: .subtitles).map(\.item) == [.screenRecording, .languages])
}

@Test func pedirUnPermisoNoImpideArrancar() {
    // El propio arranque lanza el diálogo del sistema, como hoy.
    let status = SetupStatus(inputs(microphone: .notDetermined, screen: false, requested: false))
    #expect(status.blockers(for: .voice).map(\.item) == [.microphone])
    #expect(status.startBlockers(for: .voice).isEmpty)
    #expect(status.startBlockers(for: .capture).isEmpty)
    #expect(status.startBlockers(for: .subtitles).isEmpty)
}

@Test func unPermisoDenegadoSiImpideArrancar() {
    let status = SetupStatus(inputs(microphone: .denied, screen: false, requested: true))
    #expect(status.startBlockers(for: .voice).map(\.item) == [.microphone])
    #expect(status.startBlockers(for: .capture).map(\.item) == [.screenRecording])
}
