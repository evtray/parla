import AppKit
import SwiftUI

/// Las vistas A y C: un panel sin bordes pegado al recuadro, que flota sobre
/// el juego (también a pantalla completa) y deja pasar los clics.
final class LiveOverlayPanel: NSPanel {
    enum Style { case strip, cover }

    let style: Style

    init(style: Style, session: LiveSession) {
        self.style = style
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = switch style {
        case .strip: NSHostingView(rootView: LiveSubtitleStrip(session: session))
        case .cover: NSHostingView(rootView: LiveCover(session: session))
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A va justo encima del recuadro (debajo si no cabe); C, encima de él.
    func place(over region: CGRect) {
        let frame: CGRect
        switch style {
        case .cover:
            frame = region
        case .strip:
            let height: CGFloat = 90
            let width = max(region.width, 420)
            let x = region.midX - width / 2
            let screenTop = NSScreen.screens
                .first { $0.frame.intersects(region) }?.visibleFrame.maxY ?? .greatestFiniteMagnitude
            let above = region.maxY + 6
            let y = above + height <= screenTop ? above : region.minY - height - 6
            frame = CGRect(x: x, y: y, width: width, height: height)
        }
        if self.frame != frame { setFrame(frame, display: true) }
    }
}

/// A: la última traducción, con el estilo de los subtítulos.
struct LiveSubtitleStrip: View {
    let session: LiveSession

    var body: some View {
        VStack {
            if let spanish = session.latestSpanish {
                Text(spanish)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.2), value: session.latestSpanish)
    }
}
