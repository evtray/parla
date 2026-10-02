import Testing
import Foundation
import CoreGraphics
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
