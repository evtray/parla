import Testing
import Foundation
import SwiftUI
import ParlaCore
@testable import Parla

@Test func empiezaPorElSaludo() {
    #expect(WelcomeFlow().step == .hello)
}

@Test func ahoraNoAvanzaHastaElFinalYAhiSeQueda() {
    var flow = WelcomeFlow()
    flow.advance()
    #expect(flow.step == .key)
    flow.advance()
    flow.advance()
    #expect(flow.step == .ready)
    #expect(flow.isLast)
    flow.advance()
    #expect(flow.step == .ready)
}

@Test func unaClaveBuenaPasaALosPermisos() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(.valid, hasSavedKey: true)
    #expect(flow.step == .permissions)
    #expect(flow.keyMessage == nil)
}

@Test func unaClaveRechazadaSeQuedaEnElPasoConElMotivo() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(.invalid, hasSavedKey: false)
    #expect(flow.step == .key)
    #expect(flow.keyMessage == KeyCheck.invalid.message)
}

@Test func sinRedAvanzaYLoAvisaUnaSolaVez() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(.unverified, hasSavedKey: true)
    #expect(flow.step == .permissions)
    #expect(flow.keyMessage == KeyCheck.unverified.message)
    flow.advance()
    #expect(flow.keyMessage == nil)
}

@Test func continuarConElCampoVacioYUnaClaveGuardadaAvanza() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(nil, hasSavedKey: true)
    #expect(flow.step == .permissions)
}

@Test func continuarSinNingunaClavePideUna() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(nil, hasSavedKey: false)
    #expect(flow.step == .key)
    #expect(flow.keyMessage == "Pega tu clave o pulsa «Ahora no».")
}

@Test @MainActor func cerrarLaVentanaDeBienvenidaLaDaPorVista() {
    let name = "parla-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = Preferences(defaults: defaults)
    let coordinator = WindowCoordinator(preferences: preferences,
                                        studioContent: { _ in AnyView(EmptyView()) },
                                        welcomeContent: { AnyView(EmptyView()) })
    coordinator.showWelcome()
    #expect(!preferences.hasSeenWelcome)
    // Igual que el botón rojo de la ventana, a mitad de cualquier paso.
    coordinator.closeWelcome()
    #expect(preferences.hasSeenWelcome)
}
