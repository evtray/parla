// Solo en Debug: usa una API privada de AppKit (`statusItem`) y variables de
// entorno que no deben existir en la app que se distribuye.
#if DEBUG
import AppKit

/// Afordancias de desarrollo para ejercitar la interfaz desde la terminal, donde
/// no se puede hacer clic. Solo actúan si su variable de entorno está puesta.
@MainActor
enum DebugHooks {

    /// `PARLA_OPEN_MENU=1` y `PARLA_CLICK_AFTER=4`: a los 4 s abre el menú
    /// emergente, igual que un clic en el icono.
    /// `PARLA_APPEARANCE=dark` (o `light`): fuerza la apariencia de la app, para
    /// revisar los dos modos sin tocar los ajustes del sistema.
    static func install() {
        let environment = ProcessInfo.processInfo.environment
        if environment["PARLA_PROBE_AUDIO"] == "1" { probeAudio() }
        if let delays = environment["PARLA_SNAPSHOT_AFTER"] {
            for delay in delays.split(separator: ",").compactMap({ Double($0) }) {
                scheduleSnapshot(after: delay)
            }
        }
        switch environment["PARLA_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        guard environment["PARLA_OPEN_MENU"] == "1" else { return }
        let delay = environment["PARLA_CLICK_AFTER"].flatMap(Double.init) ?? 4

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            logWindows("antes")
            openMenuBarWindow()
            // La activación es asíncrona y el usuario puede estar usando otra
            // app: una línea de tiempo distingue "nunca se activó" de "se
            // activó y perdió el foco".
            for milliseconds in [50, 150, 300, 500, 500] {
                try? await Task.sleep(for: .milliseconds(milliseconds))
                let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                Log.pipeline.info("hook: activa=\(NSApp.isActive) "
                    + "clave=«\(NSApp.keyWindow?.title ?? "ninguna")» al frente=\(front)")
            }
            logWindows("después")
        }
    }

    /// `PARLA_PROBE_AUDIO=1`: lista los dispositivos y comprueba que el sandbox
    /// deja escribir la salida del sistema. Escribe la que ya está puesta, así
    /// que no cambia nada ni corta lo que esté sonando.
    private static func probeAudio() {
        let output = AudioDevices.defaultOutput
        let input = AudioDevices.defaultInput
        for device in AudioDevices.all() {
            let marks = (device.id == input ? " ←entrada" : "")
                + (device.id == output ? " ←salida" : "")
            Log.audio.info("hook: dispositivo «\(device.name)» uid=\(device.uid) "
                + "entrada=\(device.hasInput) salida=\(device.hasOutput)\(marks)")
        }
        guard let output else {
            Log.audio.error("hook: el sistema no tiene salida por defecto")
            return
        }
        Log.audio.info("hook: escribir la salida del sistema → OSStatus "
            + "\(AudioDevices.setDefaultOutput(output))")
    }

    /// Sin activar antes la app, la ventana del menú emergente se abre y se
    /// cierra sola, porque no llega a ser la ventana clave (sonda 1).
    private static func openMenuBarWindow() {
        let buttons = NSApp.windows
            .filter { $0.className.contains("StatusBar") }
            .compactMap { ($0.value(forKey: "statusItem") as? NSStatusItem)?.button }
        Log.pipeline.info("hook: \(buttons.count) botón(es) de barra")
        NSApp.activate(ignoringOtherApps: true)
        buttons.forEach { $0.performClick(nil) }
    }

    /// `PARLA_SNAPSHOT_AFTER=3,8`: a los 3 s y a los 8 s guarda una imagen de
    /// cada ventana visible de Parla en el `tmp` del contenedor. Las capturas de
    /// pantalla de fuera no ven una app de la barra de menús; la app sí puede
    /// dibujarse a sí misma, sin permiso de Grabación de pantalla.
    private static func scheduleSnapshot(after delay: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            let folder = FileManager.default.temporaryDirectory.appending(path: "parla-snapshots")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let file = folder.appending(path: "\(Int(delay * 10))-\(index)-\(window.className).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
                Log.pipeline.info("hook: instantánea \(file.path)")
            }
            logWindows("instantánea a los \(delay) s")
        }
    }

    private static func logWindows(_ moment: String) {
        Log.pipeline.info("hook: ventanas \(moment), app activa=\(NSApp.isActive)")
        for window in NSApp.windows {
            Log.pipeline.info("hook:   \(window.className) «\(window.title)» "
                + "visible=\(window.isVisible) key=\(window.isKeyWindow) "
                + "nivel=\(window.level.rawValue) marco=\(window.frame)")
        }
    }
}
#endif
