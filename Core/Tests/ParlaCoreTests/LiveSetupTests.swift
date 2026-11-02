import Testing
import CoreGraphics
import Foundation
@testable import ParlaCore

@Test func laFraccionYElRecorteSonInversos() {
    let fraction = LiveGeometry.fraction(of: CGRect(x: 140, y: 500, width: 720, height: 120),
                                         in: CGRect(x: 100, y: 50, width: 800, height: 600))
    #expect(abs(fraction.minX - 0.05) < 1e-9)
    #expect(abs(fraction.minY - 0.75) < 1e-9)
    #expect(abs(fraction.width - 0.9) < 1e-9)
    #expect(abs(fraction.height - 0.2) < 1e-9)
    #expect(LiveGeometry.pixelRect(fraction: fraction, imageWidth: 1600, imageHeight: 1200)
            == CGRect(x: 80, y: 900, width: 1440, height: 240))
}

@Test func elRecorteEscalaConLaImagen() {
    let fraction = CGRect(x: 0.05, y: 0.75, width: 0.9, height: 0.2)
    #expect(LiveGeometry.pixelRect(fraction: fraction, imageWidth: 800, imageHeight: 600)
            == CGRect(x: 40, y: 450, width: 720, height: 120))
}

@Test func elRecorteNoSeSaleDeLaImagen() {
    let rect = LiveGeometry.pixelRect(fraction: CGRect(x: 0.9, y: 0.9, width: 0.3, height: 0.3),
                                      imageWidth: 1000, imageHeight: 500)
    #expect(rect == CGRect(x: 900, y: 450, width: 100, height: 50))
}

@Test func reencuentraLaVentanaPorTituloYSiNoLaMasGrande() {
    let small = WindowCandidate(windowID: 1, bundleID: "com.afk", title: "Launcher",
                                frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let big = WindowCandidate(windowID: 2, bundleID: "com.afk", title: "AFK Journey 1.2",
                              frame: CGRect(x: 0, y: 0, width: 1600, height: 900))
    let other = WindowCandidate(windowID: 3, bundleID: "com.other", title: "Launcher",
                                frame: CGRect(x: 0, y: 0, width: 2000, height: 1200))
    let all = [small, big, other]
    #expect(LiveGeometry.pickWindow(for: .window(bundleID: "com.afk", title: "Launcher"),
                                    among: all) == small)
    #expect(LiveGeometry.pickWindow(for: .window(bundleID: "com.afk", title: "AFK Journey 1.3"),
                                    among: all) == big)
    #expect(LiveGeometry.pickWindow(for: .window(bundleID: "com.gone", title: "x"),
                                    among: all) == nil)
    #expect(LiveGeometry.pickWindow(for: .screen, among: all) == nil)
}

@Test func recordarGuardaLaUltimaYLaDeSuApp() {
    var memory = LiveSetupMemory()
    let game = LiveSetup(source: .window(bundleID: "com.afk", title: "AFK"),
                         region: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2), notebookID: UUID())
    memory.remember(game)
    #expect(memory.last == game)
    #expect(memory.byApp["com.afk"] == game)
    let screen = LiveSetup(source: .screen, region: CGRect(x: 10, y: 10, width: 300, height: 80),
                           notebookID: nil)
    memory.remember(screen)
    #expect(memory.last == screen)
    #expect(memory.byApp.count == 1)
}
