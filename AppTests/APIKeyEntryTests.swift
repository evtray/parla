import Testing
import Foundation
import ParlaCore
@testable import Parla

private struct StatusStreamer: HTTPStreamer {
    let status: Int
    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        HTTPStreamResponse(statusCode: status, lines: AsyncThrowingStream { $0.finish() })
    }
}

private struct OfflineStreamer: HTTPStreamer {
    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
private final class SavedKeys {
    var values: [String] = []
}

@MainActor
private func keyField(_ streamer: any HTTPStreamer, saved: SavedKeys) -> APIKeyEntry {
    APIKeyEntry(validator: APIKeyValidator(streamer: streamer),
                save: { saved.values.append($0) })
}

@Test @MainActor func unaClaveBuenaSeGuardaSinEspacios() async {
    let saved = SavedKeys()
    let field = keyField(StatusStreamer(status: 200), saved: saved)
    field.text = "  sk-ant-abc\n"
    #expect(await field.submit() == .valid)
    #expect(saved.values == ["sk-ant-abc"])
    #expect(field.text.isEmpty)
    #expect(field.message == KeyCheck.valid.message)
}

@Test @MainActor func unCampoVacioNuncaBorraLaClaveGuardada() async {
    // Guardar una cadena vacía en el Llavero borra la clave que hay.
    let saved = SavedKeys()
    let field = keyField(StatusStreamer(status: 200), saved: saved)
    field.text = "   \n"
    #expect(await field.submit() == nil)
    #expect(saved.values.isEmpty)
}

@Test @MainActor func unaClaveRechazadaNoSeGuardaYSeQuedaEnElCampo() async {
    let saved = SavedKeys()
    let field = keyField(StatusStreamer(status: 401), saved: saved)
    field.text = "sk-ant-mala"
    #expect(await field.submit() == .invalid)
    #expect(saved.values.isEmpty)
    #expect(field.text == "sk-ant-mala")
    #expect(field.message == KeyCheck.invalid.message)
}

@Test @MainActor func sinRedSeGuardaConAviso() async {
    let saved = SavedKeys()
    let field = keyField(OfflineStreamer(), saved: saved)
    field.text = "sk-ant-abc"
    #expect(await field.submit() == .unverified)
    #expect(saved.values == ["sk-ant-abc"])
    #expect(field.message == KeyCheck.unverified.message)
}
