import Testing
@testable import ParlaCore

@Test func sinNadaSonandoSeLeeAlMomento() {
    var queue = SpeechQueue()
    #expect(queue.enqueue("Hola.") == "Hola.")
    #expect(queue.speaking == "Hola.")
}

@Test func mientrasSuenaUnaFraseLaSiguienteEspera() {
    var queue = SpeechQueue()
    _ = queue.enqueue("Primera.")
    #expect(queue.enqueue("Segunda.") == nil)
    #expect(queue.waiting == "Segunda.")
}

@Test func paraIrAlDiaLaMasNuevaReemplazaALaQueEspera() {
    var queue = SpeechQueue()
    _ = queue.enqueue("Primera.")
    _ = queue.enqueue("Segunda.")
    _ = queue.enqueue("Tercera.")
    #expect(queue.waiting == "Tercera.")
    #expect(queue.finished() == "Tercera.")
}

@Test func alTerminarSinNadaPendienteQuedaEnSilencio() {
    var queue = SpeechQueue()
    _ = queue.enqueue("Única.")
    #expect(queue.finished() == nil)
    #expect(queue.speaking == nil)
    // Y la siguiente vuelve a leerse al momento.
    #expect(queue.enqueue("Otra.") == "Otra.")
}
