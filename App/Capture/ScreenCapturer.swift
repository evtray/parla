import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Selecciona una región con `SelectionOverlay` y la captura con
/// ScreenCaptureKit, que sí funciona dentro del sandbox.
struct ScreenCapturer: Sendable {

    enum Failure: Error, Equatable {
        /// Sin el permiso, macOS no falla: devuelve las ventanas en blanco. Por
        /// eso se comprueba antes y no se intenta adivinar mirando la imagen.
        case noPermission
        case failed(status: Int32)
    }

    let hasPermission: @Sendable () -> Bool
    /// Coordenadas globales de AppKit; `nil` si se canceló.
    let select: @Sendable () async -> CGRect?
    /// Devuelve el PNG de ese rectángulo.
    let grab: @Sendable (CGRect) async throws -> Data

    static let live = ScreenCapturer(
        hasPermission: { CGPreflightScreenCaptureAccess() },
        select: { await SelectionOverlay.selectRegion() },
        grab: { rect in
            let primaryHeight = await MainActor.run { NSScreen.screens.first?.frame.height ?? 0 }
            let image = try await SCScreenshotManager.captureImage(
                in: displaySpace(rect, primaryHeight: primaryHeight))
            return try ImageDownscaler.encode(image, as: .png)
        })

    /// `nil` si el usuario canceló con Esc.
    func captureRegion() async throws -> Data? {
        guard hasPermission() else { throw Failure.noPermission }
        guard let rect = await select() else { return nil }
        // La capa tiene que haber desaparecido antes de la foto.
        try await Task.sleep(for: .milliseconds(80))
        return try await grab(rect)
    }

    /// AppKit mide desde abajo a la izquierda de la pantalla principal;
    /// ScreenCaptureKit, desde arriba a la izquierda.
    static func displaySpace(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
