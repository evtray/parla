import Testing
@testable import Parla

private let fifine = AudioDevice(id: 71, uid: "usb-fifine", name: "Fifine",
                                 hasInput: true, hasOutput: false)
private let airpods = AudioDevice(id: 84, uid: "bt-airpods", name: "AirPods",
                                  hasInput: true, hasOutput: true)
private let speakers = AudioDevice(id: 60, uid: "builtin-speakers", name: "Altavoces",
                                   hasInput: false, hasOutput: true)
private let connected = [fifine, airpods, speakers]

@Test func elMicroElegidoSeEncuentraPorSuUID() {
    #expect(AudioDevices.input(preferredUID: "usb-fifine", among: connected) == fifine)
}

@Test func sinMicroElegidoNoSeFuerzaNinguno() {
    #expect(AudioDevices.input(preferredUID: nil, among: connected) == nil)
}

@Test func unMicroDesenchufadoNoSeFuerza() {
    // El UID sigue guardado aunque el dispositivo ya no esté: la captura tiene
    // que caer al micro del sistema, no quedarse apuntando a la nada.
    #expect(AudioDevices.input(preferredUID: "usb-desaparecido", among: connected) == nil)
}

@Test func unDispositivoSoloDeSalidaNoSirveDeMicro() {
    #expect(AudioDevices.input(preferredUID: "builtin-speakers", among: connected) == nil)
}
