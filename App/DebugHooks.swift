// Solo en Debug: usa una API privada de AppKit (`statusItem`) y variables de
// entorno que no deben existir en la app que se distribuye.
#if DEBUG
import AppKit
import CoreMedia
@preconcurrency import ScreenCaptureKit

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
        if environment["PARLA_PROBE_LIVE"] == "1" {
            probeLive(bundleID: environment["PARLA_PROBE_BUNDLE"])
        }
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

    /// `PARLA_PROBE_LIVE=1 PARLA_PROBE_BUNDLE=<id>`: las sondas 2, 3 y 5 de la
    /// lectura en vivo. Lista las ventanas (5), muestra un panel rojo con el
    /// mismo nivel que los subtítulos (3) y, a los 8 s, cuenta durante 20 s los
    /// fotogramas que llegan de la ventana del juego a 2 fps (2).
    private static func probeLive(bundleID: String?) {
        let panel = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 300, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.backgroundColor = NSColor.systemRed.withAlphaComponent(0.6)
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        probePanel = panel

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: false)
                for window in content.windows {
                    Log.audio.info("sonda 5: «\(window.owningApplication?.bundleIdentifier ?? "sin bundle")» "
                        + "app=«\(window.owningApplication?.applicationName ?? "?")» "
                        + "título=«\(window.title ?? "")» marco=\(window.frame) "
                        + "en pantalla=\(window.isOnScreen)")
                }
                try await Task.sleep(for: .seconds(8))
                guard let bundleID,
                      let window = content.windows.first(where: {
                          $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.width >= 100
                      })
                else {
                    Log.audio.error("sonda 2: no hay ventana de «\(bundleID ?? "nil")»")
                    return
                }
                let configuration = SCStreamConfiguration()
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                configuration.width = Int(window.frame.width)
                configuration.height = Int(window.frame.height)
                let counter = ProbeFrameCounter()
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                                      configuration: configuration, delegate: nil)
                try stream.addStreamOutput(counter, type: .screen, sampleHandlerQueue: counter.queue)
                try await stream.startCapture()
                for second in 1...20 {
                    try await Task.sleep(for: .seconds(1))
                    Log.audio.info("sonda 2: segundo \(second): \(counter.takeCount()) fotograma(s) completos")
                }
                try await stream.stopCapture()
                Log.audio.info("sonda 2: fin")
            } catch {
                Log.audio.error("sonda live: \(error.localizedDescription)")
            }
        }
    }

    private static var probePanel: NSPanel?

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

/// Cuenta los fotogramas `.complete` del stream de la sonda 2.
private final class ProbeFrameCounter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.schoolaid.Parla.sonda-live")
    private let lock = NSLock()
    private var count = 0

    func takeCount() -> Int {
        lock.withLock { defer { count = 0 }; return count }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete
        else { return }
        lock.withLock { count += 1 }
    }
}
#endif
