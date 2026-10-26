import Testing
import Foundation
import ParlaCore
@testable import Parla

/// Un almacén propio por test: los ajustes reales de Parla no se tocan.
private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "parla-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@Test func elModeloElegidoSobreviveAReabrirLaApp() {
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).model = .sonnet55
        #expect(Preferences(defaults: defaults).model == .sonnet55)
    }
}

@Test func unModeloGuardadoQueYaNoExisteCaeAlPorDefecto() {
    // Un identificador de una versión anterior de Parla, o de un modelo
    // retirado, no puede dejar la app sin modelo con el que traducir.
    withScratchDefaults { defaults in
        defaults.set("claude-opus-4-1", forKey: "model")
        #expect(Preferences(defaults: defaults).model == .opus55)
    }
}

@Test func laPeticionLlevaElModeloElegido() throws {
    let utterance = Utterance(text: "hola", startedAt: Date(timeIntervalSince1970: 0))
    let request = try ClaudeModel.sonnet55.requestBuilder
        .makeRequest(for: utterance, apiKey: "k")
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["model"] as? String == "claude-sonnet-5-5")
}

@Test func elModoDeTraduccionSobreviveAReabrirLaApp() {
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).translationMode = .batch
        #expect(Preferences(defaults: defaults).translationMode == .batch)
    }
}

@Test func elMicroElegidoSobreviveAReabrirLaApp() {
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).inputDeviceUID = "usb-fifine"
        #expect(Preferences(defaults: defaults).inputDeviceUID == "usb-fifine")
    }
}

@Test func volverAlMicroDelSistemaOlvidaElElegido() {
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).inputDeviceUID = "usb-fifine"
        Preferences(defaults: defaults).inputDeviceUID = nil
        #expect(Preferences(defaults: defaults).inputDeviceUID == nil)
    }
}

@Test func leerEnVozAltaVieneEncendido() {
    withScratchDefaults { defaults in
        #expect(Preferences(defaults: defaults).readsSubtitlesAloud)
    }
}

@Test func apagarLaVozSobreviveAReabrirLaApp() {
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).readsSubtitlesAloud = false
        #expect(!Preferences(defaults: defaults).readsSubtitlesAloud)
    }
}

@Test func laBienvenidaNoSeHaVistoAlEmpezar() {
    withScratchDefaults { defaults in
        #expect(!Preferences(defaults: defaults).hasSeenWelcome)
    }
}

@Test func haberVistoLaBienvenidaSobreviveAReabrir() {
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).hasSeenWelcome = true
        #expect(Preferences(defaults: defaults).hasSeenWelcome)
    }
}

@Test func laPantallaNoSeHaPedidoAlEmpezar() {
    withScratchDefaults { defaults in
        #expect(!Preferences(defaults: defaults).screenRecordingRequested)
    }
}

@Test func haberPedidoLaPantallaSobreviveAReabrir() {
    // macOS solo enseña su diálogo una vez por app: volver a pedirlo no hace nada.
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).screenRecordingRequested = true
        #expect(Preferences(defaults: defaults).screenRecordingRequested)
    }
}
