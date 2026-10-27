import Testing
import CoreGraphics
import Foundation
import ParlaCore
@testable import Parla

private let game = WindowCandidate(windowID: 7, bundleID: "com.afk", title: "AFK Journey",
                                   frame: CGRect(x: 0, y: 0, width: 1600, height: 900))
private let remembered = LiveSetup(source: .window(bundleID: "com.afk", title: "AFK Journey"),
                                   region: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2),
                                   notebookID: UUID())

@Test func conUnaConfiguracionRecordadaArrancaSinPreguntar() {
    let model = LiveSetupFlowModel(memory: LiveSetupMemory(last: remembered,
                                                           byApp: ["com.afk": remembered]),
                                   windows: [game])
    #expect(model.nextStep == nil)
    #expect(model.setup == remembered)
}

@Test func sinLaVentanaRecordadaEmpiezaPorLaFuente() {
    let model = LiveSetupFlowModel(memory: LiveSetupMemory(last: remembered,
                                                           byApp: ["com.afk": remembered]),
                                   windows: [])
    #expect(model.nextStep == .source)
    #expect(LiveSetupFlowModel(memory: LiveSetupMemory(), windows: [game]).nextStep == .source)
}

@Test func alElegirUnaAppRecordadaSaltaAlCuaderno() {
    var model = LiveSetupFlowModel(memory: LiveSetupMemory(byApp: ["com.afk": remembered]),
                                   windows: [game])
    model.choose(window: game)
    #expect(model.nextStep == .notebook)
    #expect(model.setup?.region == remembered.region)
}

@Test func alElegirUnaAppNuevaPideElRecuadro() {
    var model = LiveSetupFlowModel(memory: LiveSetupMemory(), windows: [game])
    model.choose(window: game)
    #expect(model.nextStep == .region)
    model.chooseRegion(CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2))
    #expect(model.nextStep == .notebook)
    model.chooseNotebook(nil)
    #expect(model.nextStep == nil)
    #expect(model.setup?.source == .window(bundleID: "com.afk", title: "AFK Journey"))
}
