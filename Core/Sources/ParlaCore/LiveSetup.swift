import CoreGraphics
import Foundation

/// De dónde se lee: una ventana (que se reencuentra aunque se mueva) o un
/// recuadro fijo de la pantalla.
public enum LiveSource: Codable, Sendable, Equatable {
    case window(bundleID: String, title: String)
    case screen
}

public enum LiveRhythm: String, Codable, Sendable, CaseIterable {
    /// Lee cada fotograma y traduce lo que cambia.
    case automatic
    /// «Cuando yo diga»: solo lee con «Leer ahora».
    case onDemand
}

/// Dónde se ve la traducción: A, B o C del spec.
public enum LiveDisplay: String, Codable, Sendable, CaseIterable {
    case subtitle, panel, cover
}

/// `region`: con `.window`, fracciones 0…1 de la ventana con origen ARRIBA a la izquierda (como
/// la imagen del stream); con `.screen`, coordenadas globales de ScreenCaptureKit (también arriba).
public struct LiveSetup: Codable, Sendable, Equatable {
    public var source: LiveSource
    public var region: CGRect
    public var notebookID: UUID?

    public init(source: LiveSource, region: CGRect, notebookID: UUID?) {
        self.source = source
        self.region = region
        self.notebookID = notebookID
    }
}

public struct WindowCandidate: Sendable, Equatable {
    public let windowID: UInt32
    public let bundleID: String
    public let title: String
    public let frame: CGRect

    public init(windowID: UInt32, bundleID: String, title: String, frame: CGRect) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
    }
}

public enum LiveGeometry {
    /// El recuadro como fracción de la ventana: así sobrevive a que la
    /// ventana cambie de tamaño o de pantalla.
    public static func fraction(of rect: CGRect, in window: CGRect) -> CGRect {
        guard window.width > 0, window.height > 0 else { return .zero }
        return CGRect(x: (rect.minX - window.minX) / window.width,
                      y: (rect.minY - window.minY) / window.height,
                      width: rect.width / window.width,
                      height: rect.height / window.height)
    }

    /// En píxeles enteros, redondeado hacia fuera y dentro de la imagen.
    public static func pixelRect(fraction: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        // La tolerancia evita que 1520.0000000002 se convierta en 1521.
        let epsilon = 1e-6
        let width = Double(imageWidth), height = Double(imageHeight)
        let minX = max(0, (fraction.minX * width + epsilon).rounded(.down))
        let minY = max(0, (fraction.minY * height + epsilon).rounded(.down))
        let maxX = min(width, (fraction.maxX * width - epsilon).rounded(.up))
        let maxY = min(height, (fraction.maxY * height - epsilon).rounded(.up))
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// El mismo título dentro de la app y, si no, la ventana más grande de esa app.
    public static func pickWindow(for source: LiveSource,
                                  among candidates: [WindowCandidate]) -> WindowCandidate? {
        guard case let .window(bundleID, title) = source else { return nil }
        let sameApp = candidates.filter { $0.bundleID == bundleID }
        return sameApp.first { $0.title == title }
            ?? sameApp.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}

/// Lo último que se usó y lo último por app: volver a ⌃⌥L con el mismo juego
/// arranca sin preguntar.
public struct LiveSetupMemory: Codable, Sendable, Equatable {
    public var last: LiveSetup?
    public var byApp: [String: LiveSetup]

    public init(last: LiveSetup? = nil, byApp: [String: LiveSetup] = [:]) {
        self.last = last
        self.byApp = byApp
    }

    public mutating func remember(_ setup: LiveSetup) {
        last = setup
        if case let .window(bundleID, _) = setup.source { byApp[bundleID] = setup }
    }
}
