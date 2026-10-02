import CoreAudio
import SwiftUI
import KeyboardShortcuts

struct SettingsSection: View {
    @Bindable var state: AppState
    @State private var keyEntry = APIKeyEntry()
    /// Se pregunta sin leer la clave: el Llavero no pide contraseña.
    @State private var hasKey = false

    private var systemInputLabel: String {
        state.audioDevices.defaultInputName.map { "El del sistema (\($0))" }
            ?? "El del sistema"
    }

    /// El UID guardado, si su dispositivo ya no está entre los conectados.
    private var missingInputUID: String? {
        guard let uid = state.inputDeviceUID,
              !state.audioDevices.inputs.contains(where: { $0.uid == uid })
        else { return nil }
        return uid
    }

    /// La salida no se guarda: es la del sistema, y se lee y se escribe ahí.
    private var systemOutput: Binding<AudioDeviceID?> {
        Binding(get: { state.audioDevices.defaultOutputID },
                set: { if let id = $0 { state.audioDevices.selectOutput(id) } })
    }

    var body: some View {
        Form {
            Section("Clave de la API de Anthropic") {
                SecureField("Clave", text: $keyEntry.text,
                            prompt: Text(hasKey ? "Guardada; pega otra para cambiarla" : "sk-ant-…"))
                    .onSubmit(saveKey)
                HStack {
                    Button("Guardar", action: saveKey)
                    if keyEntry.isChecking { ProgressView().controlSize(.small) }
                }
                if let message = keyEntry.message {
                    Text(message).font(.caption)
                }
                Text("Se guarda en el Llavero de macOS, nunca en un archivo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Modelo") {
                Picker("Traducir con", selection: $state.model) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                Text(state.model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            Section("Audio") {
                Picker("Micrófono", selection: $state.inputDeviceUID) {
                    Text(systemInputLabel).tag(String?.none)
                    ForEach(state.audioDevices.inputs) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                    // Sin esta fila, un micro guardado y desenchufado deja el
                    // selector en blanco y sin forma de saber qué pasa.
                    if let missing = missingInputUID {
                        Text("Micrófono no conectado").tag(String?.some(missing))
                    }
                }
                Picker("Salida del sistema", selection: systemOutput) {
                    ForEach(state.audioDevices.outputs) { device in
                        Text(device.name).tag(AudioDeviceID?.some(device.id))
                    }
                }
                Text("El micrófono vale para la próxima vez que enciendas la escucha. "
                     + "La salida cambia la de todo el Mac, igual que Ajustes del "
                     + "Sistema › Sonido.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Subtítulos") {
                Toggle("Leer la traducción en voz alta", isOn: $state.readsSubtitlesAloud)
                Text("Usa una voz en español de tu Mac. Las voces «mejoradas» suenan más "
                     + "naturales y se descargan gratis en Ajustes del Sistema › "
                     + "Accesibilidad › Contenido leído.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Atajo") {
                KeyboardShortcuts.Recorder("Encender y apagar la escucha:",
                                          name: .toggleListening)
                KeyboardShortcuts.Recorder("Capturar pantalla:", name: .captureScreen)
                KeyboardShortcuts.Recorder("Mostrar u ocultar subtítulos:", name: .toggleSubtitles)
            }
            Section("Bienvenida") {
                Button("Ver la bienvenida otra vez") { state.windows.showWelcome() }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasKey = KeychainStore.shared.hasAPIKey
            state.audioDevices.start()
        }
    }

    private func saveKey() {
        Task {
            await keyEntry.submit()
            hasKey = KeychainStore.shared.hasAPIKey
            state.setup.refreshNow()
        }
    }
}
