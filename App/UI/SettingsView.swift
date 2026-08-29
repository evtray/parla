import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleListening = Self("toggleListening",
                                      default: .init(.space, modifiers: [.control, .option]))
}

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var apiKey = KeychainStore.shared.apiKey ?? ""

    var body: some View {
        Form {
            Section("Clave de la API de Anthropic") {
                SecureField("sk-ant-…", text: $apiKey)
                    .onSubmit { KeychainStore.shared.apiKey = apiKey }
                Text("Se guarda en el Llavero de macOS, nunca en un archivo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Guardar") { KeychainStore.shared.apiKey = apiKey }
            }
            Section("Cuándo traducir") {
                Picker("", selection: $state.mode) {
                    ForEach(TranslationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(state.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Atajo") {
                KeyboardShortcuts.Recorder("Encender y apagar la escucha:",
                                          name: .toggleListening)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
