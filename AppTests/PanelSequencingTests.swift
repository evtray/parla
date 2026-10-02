import Testing
import ParlaCore
@testable import Parla

/// El panel es lo único que se ve al arrancar un modo con un atajo: lo que
/// falla tiene que quedar en él.
@Test @MainActor func siDeniegasElMicrofonoElPanelLoDice() {
    let state = AppState()
    defer { state.hidePanel() }
    state.voiceFailedToStart(TranscriberSetupError.microphoneDenied)
    #expect(state.blockedMode == .voice)
}

@Test @MainActor func elPanelSePuedeCerrarAunqueSeQuedeSinNada() {
    let state = AppState()
    defer { state.hidePanel() }
    state.voiceFailedToStart(TranscriberSetupError.localeUnsupported)
    #expect(state.setupError != nil)
    state.dismiss(.setup(state.setupError ?? ""))
    #expect(state.panelCanClose)
}
