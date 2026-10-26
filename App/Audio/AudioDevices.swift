import CoreAudio
import Foundation
import Observation

/// Un dispositivo de audio tal como lo ve CoreAudio.
struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    /// Estable entre reinicios y reconexiones; el `id` no lo es. Es lo que se
    /// guarda en las preferencias.
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}

enum AudioDevices {

    // MARK: - Elección

    /// El micrófono que hay que forzar, o `nil` si toca usar el del sistema:
    /// porque no se eligió ninguno, porque el elegido ya no está conectado o
    /// porque ese dispositivo no tiene entrada.
    static func input(preferredUID: String?, among devices: [AudioDevice]) -> AudioDevice? {
        guard let preferredUID else { return nil }
        return devices.first { $0.uid == preferredUID && $0.hasInput }
    }

    // MARK: - CoreAudio

    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func property(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func all() -> [AudioDevice] {
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr
        else { return [] }

        var ids = [AudioDeviceID](repeating: 0,
                                  count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap(device)
    }

    static var defaultOutput: AudioDeviceID? {
        defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    static var defaultInput: AudioDeviceID? {
        defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// Cambia la salida de todo el Mac, igual que Ajustes del Sistema › Sonido.
    static func setDefaultOutput(_ id: AudioDeviceID) -> OSStatus {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var id = id
        return AudioObjectSetPropertyData(system, &address, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = property(selector)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown
        else { return nil }
        return id
    }

    private static func device(_ id: AudioDeviceID) -> AudioDevice? {
        guard let uid = string(kAudioDevicePropertyDeviceUID, of: id),
              let name = string(kAudioObjectPropertyName, of: id)
        else { return nil }
        return AudioDevice(id: id,
                           uid: uid,
                           name: name,
                           hasInput: hasStreams(id, scope: kAudioObjectPropertyScopeInput),
                           hasOutput: hasStreams(id, scope: kAudioObjectPropertyScopeOutput))
    }

    private static func string(_ selector: AudioObjectPropertySelector,
                               of id: AudioDeviceID) -> String? {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Un dispositivo sin flujos en un sentido no sirve en ese sentido: los
    /// altavoces no tienen entrada y un micro USB no tiene salida.
    private static func hasStreams(_ id: AudioDeviceID,
                                   scope: AudioObjectPropertyScope) -> Bool {
        var address = property(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr
        else { return false }
        return size > 0
    }
}

/// La lista de dispositivos y los que el sistema usa por defecto, al día
/// aunque se enchufe algo o se cambie la salida desde otro sitio.
@MainActor
@Observable
final class AudioDeviceMonitor {

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioDeviceID?
    private(set) var defaultInputID: AudioDeviceID?

    var inputs: [AudioDevice] { devices.filter(\.hasInput) }
    var outputs: [AudioDevice] { devices.filter(\.hasOutput) }

    var defaultInputName: String? {
        devices.first { $0.id == defaultInputID }?.name
    }

    @ObservationIgnored
    private var isWatching = false

    /// Se puede llamar las veces que haga falta. No va en `init` porque las
    /// vistas de Ajustes se construyen mucho más a menudo de lo que aparecen.
    func start() {
        refresh()
        guard !isWatching else { return }
        isWatching = true

        for selector in [kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioDevices.property(selector)
            // CoreAudio llama al bloque en la cola que se le pasa: la principal.
            AudioObjectAddPropertyListenerBlock(AudioDevices.system, &address, .main) {
                @Sendable [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func selectOutput(_ id: AudioDeviceID) {
        let status = AudioDevices.setDefaultOutput(id)
        if status != noErr {
            Log.audio.error("no se pudo cambiar la salida del sistema: OSStatus \(status)")
        }
        refresh()
    }

    private func refresh() {
        devices = AudioDevices.all()
        defaultOutputID = AudioDevices.defaultOutput
        defaultInputID = AudioDevices.defaultInput
    }
}
