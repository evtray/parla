import Testing
import AppKit
@testable import Parla

@Test func elBlancoSeLeeSobreElAcentoClaro() {
    #expect(Theme.contrastRatio(Theme.Palette.accentLight, Theme.Palette.onAccentLight) >= 4.5)
}

@Test func elTextoOscuroSeLeeSobreElAcentoOscuro() {
    #expect(Theme.contrastRatio(Theme.Palette.accentDark, Theme.Palette.onAccentDark) >= 4.5)
}

@Test func elTerracotaDelIconoNoServiriaParaTexto() {
    // Por esto el acento de la interfaz no es el del icono.
    #expect(Theme.contrastRatio(Theme.Palette.iconBackground, Theme.Palette.white) < 4.5)
}

@Test func elContrasteDeNegroSobreBlancoEsVeintiuno() {
    let ratio = Theme.contrastRatio(Theme.RGB(hex: 0x000000), Theme.RGB(hex: 0xFFFFFF))
    #expect(abs(ratio - 21) < 0.01)
}

@Test func elAcentoDelCatalogoEsElDeLaPaleta() throws {
    // Si el catálogo y el código divergieran, los tests de contraste mentirían.
    let named = try #require(NSColor(named: "AccentColor"))
    var light: NSColor?
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        light = named.usingColorSpace(.sRGB)
    }
    let color = try #require(light)
    #expect(Int((color.redComponent * 255).rounded()) == 0xB8)
    #expect(Int((color.greenComponent * 255).rounded()) == 0x4A)
    #expect(Int((color.blueComponent * 255).rounded()) == 0x26)
}
