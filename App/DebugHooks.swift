import AppKit

/// Afordancias de desarrollo para ejercitar la interfaz desde la terminal, donde
/// no se puede hacer clic. Solo actúan si su variable de entorno está puesta.
@MainActor
enum DebugHooks {

    /// `PARLA_CLICK_MENU="Ajustes…"` y `PARLA_CLICK_AFTER=4`: a los 4 s ejecuta
    /// la acción de ese ítem del menú de la barra, igual que un clic.
    static func install() {
        let environment = ProcessInfo.processInfo.environment
        if environment["PARLA_PROBE_AUDIO"] == "1" { probeAudio() }
        guard let title = environment["PARLA_CLICK_MENU"] else { return }
        let delay = environment["PARLA_CLICK_AFTER"].flatMap(Double.init) ?? 4

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            logWindows("antes")
            clickMenuItem(titled: title)
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

    private static func clickMenuItem(titled title: String) {
        let statusItems = NSApp.windows
            .filter { $0.className.contains("StatusBar") }
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
        Log.pipeline.info("hook: \(statusItems.count) ítem(s) de barra")

        for statusItem in statusItems {
            guard let menu = statusItem.menu else {
                Log.pipeline.info("hook: el ítem de barra no tiene menú")
                continue
            }
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            let titles = menu.items.map { "\($0.title)[\($0.isEnabled ? "on" : "off")]" }
            Log.pipeline.info("hook: menú = \(titles.joined(separator: " | "))")

            guard let index = menu.items.firstIndex(where: { $0.title == title }) else {
                Log.pipeline.error("hook: no hay ítem «\(title)»")
                continue
            }
            Log.pipeline.info("hook: activa=\(NSApp.isActive) → ejecuta «\(title)»")
            menu.performActionForItem(at: index)
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
