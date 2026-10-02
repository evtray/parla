import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import Parla

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var rects: [CGRect] = []
    var grabbed: [CGRect] { lock.withLock { rects } }
    func record(_ rect: CGRect) { lock.withLock { rects.append(rect) } }
}

@Test func sinPermisoNiSiquieraAbreLaSeleccion() async {
    let recorder = Recorder()
    let capturer = ScreenCapturer(hasPermission: { false },
                                  select: { CGRect(x: 0, y: 0, width: 10, height: 10) },
                                  grab: { recorder.record($0); return Data([1]) })
    await #expect(throws: ScreenCapturer.Failure.noPermission) {
        try await capturer.captureRegion()
    }
    #expect(recorder.grabbed.isEmpty)
}

@Test func cancelarLaSeleccionEsNil() async throws {
    let capturer = ScreenCapturer(hasPermission: { true }, select: { nil },
                                  grab: { _ in Data([1]) })
    #expect(try await capturer.captureRegion() == nil)
}

@Test func capturaElRectanguloElegido() async throws {
    let recorder = Recorder()
    let rect = CGRect(x: 10, y: 20, width: 300, height: 100)
    let capturer = ScreenCapturer(hasPermission: { true }, select: { rect },
                                  grab: { recorder.record($0); return Data([7]) })
    #expect(try await capturer.captureRegion() == Data([7]))
    #expect(recorder.grabbed == [rect])
}

@Test func pasaDeCoordenadasDeAppKitALasDeLaPantalla() {
    // AppKit mide desde abajo a la izquierda de la pantalla principal;
    // ScreenCaptureKit, desde arriba a la izquierda.
    let appKit = CGRect(x: 100, y: 200, width: 300, height: 50)
    #expect(ScreenCapturer.displaySpace(appKit, primaryHeight: 1000)
            == CGRect(x: 100, y: 750, width: 300, height: 50))
}

// MARK: - La capa de selección

@MainActor
private func escape(for window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                     windowNumber: window.windowNumber, context: nil,
                     characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                     isARepeat: false, keyCode: 53)!
}

@Test @MainActor func cerrarLaCapaNoLaDejaViva() async throws {
    // Una ventana del tamaño de la pantalla por captura, para siempre, sería
    // una fuga: tras Esc, nadie puede seguir reteniendo la capa.
    let screen = try #require(NSScreen.main)
    var result: CGRect?? = .none
    weak var weakWindow: OverlayWindow?
    do {
        let window = OverlayWindow(screen: screen) { result = .some($0) }
        weakWindow = window
        window.keyDown(with: escape(for: window))
    }
    try await Task.sleep(for: .milliseconds(200))
    #expect(result == .some(nil))
    #expect(weakWindow == nil)
}

@Test @MainActor func laCapaAparecePorEncimaDeUnaAppAPantallaCompleta() throws {
    let window = OverlayWindow(screen: try #require(NSScreen.main)) { _ in }
    #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
    window.keyDown(with: escape(for: window))
}

@Test @MainActor func elPrimerClicYaEmpiezaElArrastre() {
    // Si la app aún no está activa, AppKit gasta el primer clic en activarla y
    // el arrastre no dibuja nada.
    #expect(SelectionView { _ in }.acceptsFirstMouse(for: nil))
}
