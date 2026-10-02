import Testing
import Foundation
@testable import ParlaCore

@Test func unaClaveAceptadaEsValida() async {
    #expect(await APIKeyValidator(streamer: FakeStreamer(statusCode: 200)).check("sk-ant-1") == .valid)
}

@Test func unaClaveRechazadaEsInvalida() async {
    for status in [401, 403] {
        #expect(await APIKeyValidator(streamer: FakeStreamer(statusCode: status)).check("sk-ant-1")
                == .invalid)
    }
}

@Test func otrosErroresDelServidorNoDicenNadaDeLaClave() async {
    for status in [429, 500, 529] {
        #expect(await APIKeyValidator(streamer: FakeStreamer(statusCode: status)).check("sk-ant-1")
                == .unverified)
    }
}

@Test func sinRedLaClaveQuedaSinComprobar() async {
    let offline = FakeStreamer(failWith: URLError(.notConnectedToInternet))
    #expect(await APIKeyValidator(streamer: offline).check("sk-ant-1") == .unverified)
}

@Test func elTiempoAgotadoTambienQuedaSinComprobar() async {
    let slow = FakeStreamer(failWith: URLError(.timedOut))
    #expect(await APIKeyValidator(streamer: slow).check("sk-ant-1") == .unverified)
}

@Test func seMandaLaClaveSinEspaciosNiSaltos() async {
    let streamer = ScriptedStreamer { _ in (200, []) }
    _ = await APIKeyValidator(streamer: streamer).check("  sk-ant-abc\n")
    #expect(streamer.requests.first?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-abc")
}

@Test func unaClaveVaciaEsInvalidaSinTocarLaRed() async {
    let streamer = ScriptedStreamer { _ in (200, []) }
    #expect(await APIKeyValidator(streamer: streamer).check(" \n") == .invalid)
    #expect(streamer.requests.isEmpty)
}

@Test func soloUnaClaveRechazadaNoSeGuarda() {
    #expect(KeyCheck.valid.shouldSave)
    #expect(KeyCheck.unverified.shouldSave)
    #expect(!KeyCheck.invalid.shouldSave)
}
