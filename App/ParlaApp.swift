import SwiftUI
import SwiftData
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

        // Afordancia de desarrollo: PARLA_AUTOSTART=1 enciende la escucha al
        // arrancar, para poder probar el pipeline desde la terminal sin clicar.
        if ProcessInfo.processInfo.environment["PARLA_AUTOSTART"] == "1" {
            Task { @MainActor in state.toggleListening() }
        }
        Task { @MainActor in DebugHooks.install() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.isListening ? "mic.fill" : "mic")
        }

        Settings { SettingsView(state: state) }

        Window("Historial", id: "history") { HistoryView() }
            .modelContainer(Persistence.container)
    }
}

struct MenuBarView: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// Parla vive en la barra de menús y nunca es la app activa. Sin activarla,
    /// sus ventanas se abren sin foco y detrás de las de la app en uso, que es
    /// lo mismo que no abrirse.
    ///
    /// `activate()` a secas no sirve: es cooperativa, y macOS la ignora cuando
    /// quien la pide no es ya la app en uso.
    private func inFront(_ open: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        open()
    }

    var body: some View {
        if let error = state.setupError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
        Button(state.isListening ? "Detener escucha" : "Empezar a escuchar") {
            state.toggleListening()
        }
        Button("Capturar pantalla") { state.captureScreen() }
        if state.mode == .batch, !state.pending.isEmpty {
            Button(state.pending.count == 1
                   ? "Traducir 1 frase"
                   : "Traducir \(state.pending.count) frases") {
                state.sendBatch()
            }
            .disabled(state.isSendingBatch)
        }
        Divider()
        Button("Historial…") { inFront { openWindow(id: "history") } }
        Button("Ajustes…") { inFront { openSettings() } }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Salir") { NSApplication.shared.terminate(nil) }
    }
}
