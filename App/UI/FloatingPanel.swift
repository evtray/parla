import AppKit
import SwiftUI

/// Ventana que flota sobre cualquier app y no roba el foco.
final class FloatingPanel: NSPanel {

    /// El panel de la lectura en vivo recuerda su sitio aparte del de las
    /// capturas: pueden estar abiertos a la vez.
    init<Content: View>(autosaveName: String = "ParlaFloatingPanel",
                        @ViewBuilder view: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // Sigue al usuario entre escritorios y aparece sobre apps a pantalla completa.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        contentView = NSHostingView(rootView: view())

        let hadSavedFrame = UserDefaults.standard
            .string(forKey: "NSWindow Frame \(autosaveName)") != nil
        setFrameAutosaveName(autosaveName)
        if !hadSavedFrame { positionBottomRight() }
    }

    /// Nunca es la ventana con foco: el usuario sigue escribiendo en su editor.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func positionBottomRight() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 24,
                               y: visible.minY + 24))
    }
}
