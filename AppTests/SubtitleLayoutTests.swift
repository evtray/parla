import Testing
import CoreGraphics
@testable import Parla

@Test func vaCentradaYAbajo() {
    let frame = SubtitleLayout.frame(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(frame.width == 700)
    #expect(frame.midX == 500)
    #expect(frame.minY == 64)   // un 8 % de 800
}

@Test func respetaElOrigenDeUnaSegundaPantalla() {
    let frame = SubtitleLayout.frame(in: CGRect(x: 1440, y: -200, width: 1920, height: 1080))
    // Explícito: dentro de #expect, `1440 + 960` se infiere como Int.
    #expect(frame.midX == CGFloat(1440 + 960))
    #expect(frame.minY == (-200 + 1080 * 0.08).rounded())
}

@Test func tieneAltoParaDosBloquesDeDosLineas() {
    #expect(SubtitleLayout.frame(in: CGRect(x: 0, y: 0, width: 1000, height: 800)).height
            == SubtitleLayout.height)
}

@Test func enUnaPantallaPequenaNoSeSale() {
    let screen = CGRect(x: 0, y: 0, width: 800, height: 220)
    #expect(screen.contains(SubtitleLayout.frame(in: screen)))
}
