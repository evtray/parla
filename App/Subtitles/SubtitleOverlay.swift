import AppKit
import ParlaCore
import SwiftUI

/// Dónde va la banda. La ventana es fija y transparente; el fondo oscuro solo
/// rodea al texto, así que su tamaño real lo pone el contenido.
enum SubtitleLayout {
    /// Dos bloques de hasta dos líneas a 28 pt, con márgenes.
    static let height: CGFloat = 200
    static let widthFraction: CGFloat = 0.7
    static let bottomFraction: CGFloat = 0.08

    static func frame(in screen: CGRect) -> CGRect {
        let width = (screen.width * widthFraction).rounded()
        let height = min(Self.height, screen.height - screen.height * bottomFraction)
        return CGRect(x: (screen.midX - width / 2).rounded(),
                      y: (screen.minY + screen.height * bottomFraction).rounded(),
                      width: width,
                      height: height)
    }
}

@MainActor
@Observable
final class SubtitleModel {
    var frame: SubtitleFrame?
    /// Un aviso (descarga del modelo, idiomas que faltan) en lugar del subtítulo.
    var notice: String?
    var isVisible = false
}

/// Flota sobre todo, también sobre un video a pantalla completa, y deja pasar
/// los clics: no tapa los controles del video ni roba el foco.
final class SubtitleOverlay: NSPanel {

    init(model: SubtitleModel, screen: NSScreen) {
        super.init(contentRect: SubtitleLayout.frame(in: screen.frame),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: SubtitleView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SubtitleView: View {
    let model: SubtitleModel

    var body: some View {
        VStack {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 20, weight: .medium))
                    .modifier(Banded())
            } else if model.isVisible, let frame = model.frame {
                VStack(spacing: 4) {
                    if let previous = frame.previous {
                        Text(previous)
                            .opacity(0.55)
                            .lineLimit(2)
                            .truncationMode(.head)
                    }
                    // Si no cabe, se ve el final: es lo que se acaba de decir.
                    Text(frame.current)
                        .italic(frame.currentIsOriginal)
                        .opacity(frame.currentIsOriginal ? 0.7 : 1)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
                .font(.system(size: 28, weight: .semibold))
                .modifier(Banded())
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.3), value: model.isVisible)
    }
}

/// Texto blanco centrado sobre el fondo oscuro de la banda.
private struct Banded: ViewModifier {
    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
