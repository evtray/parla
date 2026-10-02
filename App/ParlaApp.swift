import SwiftUI
import KeyboardShortcuts

@main
struct ParlaApp: App {
    @State private var state = AppState()

    init() {
        // El atajo solo existe mientras la app corre: es un hotkey global
        // registrado por el proceso, no un lanzador.
        let state = self.state
        KeyboardShortcuts.onKeyUp(for: .toggleListening) {
            Task { @MainActor in state.toggleListening() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureScreen) {
            Task { @MainActor in state.captureScreen() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleSubtitles) {
            Task { @MainActor in state.toggleSubtitles() }
        }

        #if DEBUG
        // Afordancias de desarrollo, solo en Debug: PARLA_AUTOSTART=1 enciende la
        // escucha al arrancar y PARLA_SUBTITLES_AUTOSTART=1 los subtítulos, para
        // probar desde la terminal sin clicar.
        if ProcessInfo.processInfo.environment["PARLA_SUBTITLES_AUTOSTART"] == "1" {
            Task { @MainActor in state.toggleSubtitles() }
        }
        if ProcessInfo.processInfo.environment["PARLA_AUTOSTART"] == "1" {
            Task { @MainActor in state.toggleListening() }
        }
        Task { @MainActor in DebugHooks.install() }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(state: state)
                .modelContainer(Persistence.container)
        } label: {
            // Un solo símbolo: qué modo está activo se ve en el menú emergente.
            Image(systemName: state.isListening || state.isSubtitling
                  ? "character.bubble.fill" : "character.bubble")
        }
        .menuBarExtraStyle(.window)
    }
}
