import Testing
import CoreGraphics
@testable import Parla

@Test func lasPiezasQueCabenVanEnLaMismaFila() {
    #expect(FlowLayout.rows(for: [50, 50, 50], maxWidth: 200, spacing: 6) == [[0, 1, 2]])
}

@Test func laQueNoCabeBajaALaSiguienteFila() {
    #expect(FlowLayout.rows(for: [100, 100, 100], maxWidth: 250, spacing: 6) == [[0, 1], [2]])
}

@Test func unaPiezaMasAnchaQueLaFilaVaSola() {
    // No se puede partir un chip: ocupa su fila aunque desborde.
    #expect(FlowLayout.rows(for: [300, 50], maxWidth: 250, spacing: 6) == [[0], [1]])
}

@Test func sinPiezasNoHayFilas() {
    #expect(FlowLayout.rows(for: [], maxWidth: 250, spacing: 6).isEmpty)
}
