import SwiftUI

@main
struct ParlaApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.isListening ? "mic.fill" : "mic")
        }
    }
}

struct MenuBarView: View {
    @Bindable var state: AppState

    var body: some View {
        Button(state.isListening ? "Detener escucha" : "Empezar a escuchar") {
            state.toggleListening()
        }
        Divider()
        Button("Salir") { NSApplication.shared.terminate(nil) }
    }
}
