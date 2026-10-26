import Testing
@testable import Parla

private func voice(_ language: String, _ quality: Int, _ id: String = "") -> SubtitleSpeaker.VoiceOption {
    SubtitleSpeaker.VoiceOption(identifier: id.isEmpty ? "\(language)-\(quality)" : id,
                                language: language, quality: quality)
}

@Test func prefiereElAcentoLatinoamericanoAunqueSeaDeMenorCalidad() {
    let chosen = SubtitleSpeaker.bestVoice(among: [voice("es-ES", 3), voice("es-MX", 1)])
    #expect(chosen?.language == "es-MX")
}

@Test func entreLasLatinoamericanasGanaLaDeMejorCalidad() {
    let chosen = SubtitleSpeaker.bestVoice(among: [voice("es-MX", 1), voice("es-US", 3), voice("es-MX", 2)])
    #expect(chosen?.language == "es-US")
    #expect(chosen?.quality == 3)
}

@Test func sinLatinoamericanaUsaLaDeEspana() {
    let chosen = SubtitleSpeaker.bestVoice(among: [voice("en-US", 3), voice("es-ES", 2)])
    #expect(chosen?.language == "es-ES")
}

@Test func sinVocesEnEspanolNoEligeNinguna() {
    #expect(SubtitleSpeaker.bestVoice(among: [voice("en-US", 3), voice("fr-FR", 2)]) == nil)
}

@Test func prefiereLaVozEstandarALasDeEfecto() {
    // Eddy, Flo, Grandma… son voces de efecto (`eloquence`) y suenan robóticas;
    // con la misma calidad, gana la estándar de Apple.
    let chosen = SubtitleSpeaker.bestVoice(among: [
        voice("es-MX", 1, "com.apple.eloquence.es-MX.Eddy"),
        voice("es-MX", 1, "com.apple.voice.compact.es-MX.Paulina"),
        voice("es-MX", 1, "com.apple.eloquence.es-MX.Flo"),
    ])
    #expect(chosen?.identifier == "com.apple.voice.compact.es-MX.Paulina")
}
