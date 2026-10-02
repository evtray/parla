import CoreAudio
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleListening = Self("toggleListening",
                                      default: .init(.space, modifiers: [.control, .option]))
}

struct SettingsView: View {
    @Bindable var state: AppState
    /// Se lee al aparecer y no en `init`: `Settings` construye la vista cada vez
    /// que el cuerpo de la app se reevalúa, y si el Llavero pide permiso, la
    /// lectura bloquea el hilo principal con la app entera.
    @State private var apiKey = ""

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
                SecureField("sk-ant-…", text: $apiKey)
                    .onSubmit { KeychainStore.shared.apiKey = apiKey }
                Text("Se guarda en el Llavero de macOS, nunca en un archivo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Guardar") { KeychainStore.shared.apiKey = apiKey }
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
            Section("Atajo") {
                KeyboardShortcuts.Recorder("Encender y apagar la escucha:",
                                          name: .toggleListening)
            }
        }
        .formStyle(.grouped)
        // Alto fijo y con desplazamiento: ajustada al contenido mide 830 pt y
        // no cabe en la pantalla de un portátil de 13".
        .frame(width: 420, height: 640)
        .padding()
        .onAppear {
            apiKey = KeychainStore.shared.apiKey ?? ""
            state.audioDevices.start()
        }
    }
}
