import Testing
@testable import Parla

private func voice(_ language: String, _ quality: Int, _ id: String = "") -> Speaker.VoiceOption {
    Speaker.VoiceOption(identifier: id.isEmpty ? "\(language)-\(quality)" : id,
                                language: language, quality: quality)
}

@Test func prefiereElAcentoLatinoamericanoAunqueSeaDeMenorCalidad() {
    let chosen = Speaker.bestVoice(among: [voice("es-ES", 3), voice("es-MX", 1)])
    #expect(chosen?.language == "es-MX")
}

@Test func entreLasLatinoamericanasGanaLaDeMejorCalidad() {
    let chosen = Speaker.bestVoice(among: [voice("es-MX", 1), voice("es-US", 3), voice("es-MX", 2)])
    #expect(chosen?.language == "es-US")
    #expect(chosen?.quality == 3)
}

@Test func sinLatinoamericanaUsaLaDeEspana() {
    let chosen = Speaker.bestVoice(among: [voice("en-US", 3), voice("es-ES", 2)])
    #expect(chosen?.language == "es-ES")
}

@Test func sinVocesEnEspanolNoEligeNinguna() {
    #expect(Speaker.bestVoice(among: [voice("en-US", 3), voice("fr-FR", 2)]) == nil)
}

@Test func prefiereLaVozEstandarALasDeEfecto() {
    // Eddy, Flo, Grandma… son voces de efecto (`eloquence`) y suenan robóticas;
    // con la misma calidad, gana la estándar de Apple.
    let chosen = Speaker.bestVoice(among: [
        voice("es-MX", 1, "com.apple.eloquence.es-MX.Eddy"),
        voice("es-MX", 1, "com.apple.voice.compact.es-MX.Paulina"),
        voice("es-MX", 1, "com.apple.eloquence.es-MX.Flo"),
    ])
    #expect(chosen?.identifier == "com.apple.voice.compact.es-MX.Paulina")
}

@Test func eligeUnaVozDelIdiomaQueSePide() {
    let chosen = Speaker.bestVoice(among: [voice("es-MX", 3), voice("en-US", 1)], language: "en")
    #expect(chosen?.language == "en-US")
}

@Test func enInglesPrefiereElAcentoEstadounidense() {
    let chosen = Speaker.bestVoice(among: [voice("en-GB", 3), voice("en-US", 1)], language: "en")
    #expect(chosen?.language == "en-US")
}

@Test func sinVocesDelIdiomaPedidoNoEligeNinguna() {
    #expect(Speaker.bestVoice(among: [voice("es-MX", 3)], language: "en") == nil)
}

@Test func reconoceElIdiomaDelTextoParaElegirLaVoz() {
    #expect(Speaker.language(of: "No worries if you can't make it today, we can touch base tomorrow.") == "en")
    #expect(Speaker.language(of: "Je suis désolée, je ne pourrai pas venir ce soir.") == "fr")
}

@Test func sinTextoReconocibleSuponeIngles() {
    #expect(Speaker.language(of: "") == "en")
}

@Test func nuncaEligeUnaVozDeBroma() {
    // Bells, Boing, Bad News… son voces de broma (`isNoveltyVoice`): aunque su
    // identificador ordene primero, gana la normal.
    let chosen = Speaker.bestVoice(among: [
        Speaker.VoiceOption(identifier: "com.apple.speech.synthesis.voice.Bells",
                            language: "en-US", quality: 1, isNovelty: true),
        Speaker.VoiceOption(identifier: "com.apple.voice.compact.en-US.Samantha",
                            language: "en-US", quality: 1, isNovelty: false),
    ], language: "en")
    #expect(chosen?.identifier == "com.apple.voice.compact.en-US.Samantha")
}

@Test func prefiereLasVocesModernasALasAntiguas() {
    // Fred, Ralph, Kathy… son las voces MacinTalk de antes
    // (`com.apple.speech.synthesis.voice.`): con la misma calidad, gana Samantha.
    let chosen = Speaker.bestVoice(among: [
        voice("en-US", 1, "com.apple.speech.synthesis.voice.Fred"),
        voice("en-US", 1, "com.apple.voice.compact.en-US.Samantha"),
    ], language: "en")
    #expect(chosen?.identifier == "com.apple.voice.compact.en-US.Samantha")
}
