import AppKit

/// Una capa sobre la pantalla del ratón para arrastrar un rectángulo. Existe
/// porque `screencapture -i` no funciona dentro del sandbox (sonda de la Task 1).
@MainActor
enum SelectionOverlay {

    /// El rectángulo en coordenadas globales de AppKit, o `nil` si el usuario
    /// pulsó Esc o no arrastró.
    static func selectRegion() async -> CGRect? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main
        else { return nil }

        // Para devolverle el foco al terminar: capturar no debería sacarte de lo
        // que estabas escribiendo.
        let previous = NSWorkspace.shared.frontmostApplication
        return await withCheckedContinuation { continuation in
            let window = OverlayWindow(screen: screen) { rect in
                if let previous, previous != NSRunningApplication.current { previous.activate() }
                continuation.resume(returning: rect)
            }
            // Sin activar la app, la capa no recibe el Esc.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            NSCursor.crosshair.push()
        }
    }
}

final class OverlayWindow: NSWindow {
    private let finish: (CGRect?) -> Void
    private var finished = false

    init(screen: NSScreen, finish: @escaping (CGRect?) -> Void) {
        self.finish = finish
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.15)
        // Sin esto, sobre un vídeo a pantalla completa macOS cambia de
        // escritorio en vez de poner la capa encima.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Con ARC, `true` haría que `close()` soltara una vez de más. Sin
        // retener la ventana en otro sitio, `orderOut` basta para que se libere.
        isReleasedWhenClosed = false
        contentView = SelectionView { [weak self] rect in self?.complete(rect) }
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        // 53 es Esc.
        if event.keyCode == 53 { complete(nil) } else { super.keyDown(with: event) }
    }

    private func complete(_ local: CGRect?) {
        guard !finished else { return }
        finished = true
        NSCursor.pop()
        orderOut(nil)
        let global = local.map { convertToScreen($0) }
        // Un clic sin arrastrar no es una región.
        finish(global.flatMap { $0.width >= 4 && $0.height >= 4 ? $0 : nil })
    }
}

final class SelectionView: NSView {
    private let onEnd: (CGRect?) -> Void
    private var start: CGPoint?
    private var current: CGPoint?

    init(onEnd: @escaping (CGRect?) -> Void) {
        self.onEnd = onEnd
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("no se usa desde un nib") }

    /// Si la app aún no está activa, el primer clic no se gasta en activarla:
    /// empieza el arrastre.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        onEnd(selection)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1
        border.stroke()
    }
}
