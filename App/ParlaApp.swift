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

        // Afordancia de desarrollo: PARLA_AUTOSTART=1 enciende la escucha al
        // arrancar, para poder probar el pipeline desde la terminal sin clicar.
        if ProcessInfo.processInfo.environment["PARLA_AUTOSTART"] == "1" {
            Task { @MainActor in state.toggleListening() }
        }
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

    var body: some View {
        if let error = state.setupError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
        Button(state.isListening ? "Detener escucha" : "Empezar a escuchar") {
            state.toggleListening()
        }
        if state.mode == .batch, !state.pending.isEmpty {
            Button(state.pending.count == 1
                   ? "Traducir 1 frase"
                   : "Traducir \(state.pending.count) frases") {
                state.sendBatch()
            }
            .disabled(state.isSendingBatch)
        }
        Divider()
        Button("Historial…") { openWindow(id: "history") }
        SettingsLink { Text("Ajustes…") }
        Divider()
        Button("Salir") { NSApplication.shared.terminate(nil) }
    }
}
