/// Lo que emite un `Transcriber`.
public enum TranscriptEvent: Sendable, Equatable {
    /// Resultado volátil: puede cambiar. Solo se muestra, no se acumula.
    case partial(String)
    /// Resultado finalizado: ya no cambia. Se acumula en la frase.
    case final(String)
}
