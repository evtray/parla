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
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.isListening ? "mic.fill" : "mic")
        }

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarView: View {
    @Bindable var state: AppState

    var body: some View {
        if let progress = state.downloadProgress {
            Text("Descargando modelo de español… \(Int(progress * 100))%")
                .font(.caption)
        }
        if !state.partialText.isEmpty {
            Text(state.partialText).font(.caption)
        }
        if let error = state.setupError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
        if state.needsMicrophoneAccess {
            Button("Abrir Ajustes del Sistema") { AppState.openMicrophoneSettings() }
        }
        Button(state.isListening ? "Detener escucha" : "Empezar a escuchar") {
            state.toggleListening()
        }
        SettingsLink { Text("Ajustes…") }
        Divider()
        Button("Salir") { NSApplication.shared.terminate(nil) }
    }
}
