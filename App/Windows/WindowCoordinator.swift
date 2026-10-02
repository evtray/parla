import AppKit
import SwiftUI

/// Las ventanas de Estudio y de la bienvenida.
///
/// Son `NSWindow` con contenido SwiftUI y no escenas `Window`: el panel
/// flotante también tiene que poder abrir Estudio, y fuera de las escenas de
/// SwiftUI no hay `openWindow`.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    let router = StudioRouter()

    private let preferences: Preferences
    private let studioContent: @MainActor (StudioRouter) -> AnyView
    private let welcomeContent: @MainActor () -> AnyView
    private var studio: NSWindow?
    private var welcome: NSWindow?

    init(preferences: Preferences = .shared,
         studioContent: @escaping @MainActor (StudioRouter) -> AnyView,
         welcomeContent: @escaping @MainActor () -> AnyView) {
        self.preferences = preferences
        self.studioContent = studioContent
        self.welcomeContent = welcomeContent
        super.init()
    }

    func showStudio(_ section: StudioSection? = nil) {
        router.open(section)
        let window = studio ?? makeStudioWindow()
        studio = window
        bringToFront(window)
    }

    func showWelcome() {
        if let welcome, !welcome.isVisible {
            // Siempre desde el paso 1: una vista nueva no arrastra el paso de
            // la vez anterior.
            welcome.contentViewController = NSHostingController(rootView: welcomeContent())
        }
        let window = welcome ?? makeWelcomeWindow()
        welcome = window
        window.center()
        bringToFront(window)
    }

    func closeWelcome() {
        welcome?.close()
    }

    /// Cerrarla en cualquier paso cuenta como vista: lo pendiente sigue en los
    /// avisos.
    func welcomeDidClose() {
        preferences.hasSeenWelcome = true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === welcome else { return }
        welcomeDidClose()
    }

    /// Parla vive en la barra de menús y nunca es la app activa: sin activarla,
    /// la ventana se abre detrás de la app en uso. `activate()` a secas es
    /// cooperativa y macOS la ignora cuando quien la pide no es ya la activa.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeStudioWindow() -> NSWindow {
        let controller = NSHostingController(rootView: studioContent(router))
        // La barra de herramientas de SwiftUI pasa a la ventana. El título no se
        // puentea: con `.title` la ventana se quedaba en «Untitled».
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        window.title = "Estudio"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 600))
        window.center()
        return window
    }

    private func makeWelcomeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: welcomeContent()))
        window.title = "Bienvenida a Parla"
        window.styleMask.remove([.resizable, .miniaturizable])
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
