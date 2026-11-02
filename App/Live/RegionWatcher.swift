import AppKit
import CoreGraphics
import CoreMedia
import ParlaCore
@preconcurrency import ScreenCaptureKit
import VideoToolbox

/// Las ventanas que se pueden leer: las normales de otras apps, sin las de
/// Parla y sin las diminutas (barras, iconos flotantes).
enum WindowList {
    static func candidates() async throws -> [WindowCandidate] {
        try await shareableWindows().map {
            WindowCandidate(windowID: $0.windowID,
                            bundleID: $0.owningApplication?.bundleIdentifier ?? "",
                            title: $0.title ?? "",
                            frame: $0.frame)
        }
    }

    static func shareableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: false)
        let own = Bundle.main.bundleIdentifier
        return content.windows.filter {
            $0.windowLayer == 0
                && $0.owningApplication?.bundleIdentifier != own
                && !($0.owningApplication?.bundleIdentifier ?? "").isEmpty
                && $0.frame.width >= 100 && $0.frame.height >= 100
        }
    }
}

enum RegionWatcherError: Error {
    case windowNotFound
    case noDisplay
}

/// Vigila el recuadro con ScreenCaptureKit a 2 fps y entrega la imagen ya
/// recortada. Con una ventana, el stream sigue a esa ventana aunque se mueva o
/// quede tapada; con la pantalla, lee un rectángulo fijo sin las ventanas de
/// Parla, para no leer su propia traducción.
final class RegionWatcher: FrameSource, @unchecked Sendable {

    static let frameInterval = CMTime(value: 1, timescale: 2)
    /// Sin fotogramas durante este tiempo, la ventana está oculta.
    static let silenceLimit: TimeInterval = 3

    let setup: LiveSetup

    init(setup: LiveSetup) {
        self.setup = setup
    }

    /// Con una ventana, el fotograma es la ventana entera y se recorta a la
    /// fracción; con la pantalla ya viene recortado por `sourceRect`.
    static func crop(_ image: CGImage, setup: LiveSetup) -> CGImage? {
        guard case .window = setup.source else { return image }
        let rect = LiveGeometry.pixelRect(fraction: setup.region,
                                          imageWidth: image.width, imageHeight: image.height)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return image.cropping(to: rect)
    }

    // MARK: - Stream

    func frames() -> AsyncStream<LiveFrameEvent> {
        // Si Vision va más lento que 2 fps, los fotogramas viejos sobran: solo
        // importa el más reciente.
        let (events, continuation) = AsyncStream<LiveFrameEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(3))
        let setup = setup
        let task = Task {
            let runner = StreamRunner(setup: setup, continuation: continuation)
            await runner.run()
        }
        continuation.onTermination = { _ in task.cancel() }
        return events
    }

    func snapshot() async throws -> CGImage {
        let (filter, configuration) = try await Self.filterAndConfiguration(for: setup)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: configuration)
        guard let cropped = Self.crop(image, setup: setup) else { throw RegionWatcherError.noDisplay }
        return cropped
    }

    /// El filtro y la configuración del stream o de la foto.
    static func filterAndConfiguration(for setup: LiveSetup) async throws
        -> (SCContentFilter, SCStreamConfiguration) {
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = frameInterval
        configuration.showsCursor = false
        switch setup.source {
        case .window:
            let windows = try await WindowList.shareableWindows()
            guard let window = pick(for: setup, among: windows) else {
                throw RegionWatcherError.windowNotFound
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            size(configuration, for: window.frame, scale: CGFloat(filter.pointPixelScale))
            return (filter, configuration)
        case .screen:
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            let region = setup.region
            guard let display = content.displays.first(where: { $0.frame.intersects(region) })
                ?? content.displays.first
            else { throw RegionWatcherError.noDisplay }
            let own = content.applications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            // Sin excluir a Parla, el recuadro puede leer su propia traducción;
            // la sesión aún descarta lo que se parece a ella.
            if own.isEmpty {
                Log.pipeline.error("lectura en vivo: Parla no aparece entre las apps a excluir")
            }
            let filter = SCContentFilter(display: display, excludingApplications: own,
                                         exceptingWindows: [])
            // `sourceRect` va en puntos de la pantalla, no globales.
            configuration.sourceRect = region.offsetBy(dx: -display.frame.minX,
                                                       dy: -display.frame.minY)
            size(configuration, for: region, scale: CGFloat(filter.pointPixelScale))
            return (filter, configuration)
        }
    }

    static func pick(for setup: LiveSetup, among windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.map {
            WindowCandidate(windowID: $0.windowID,
                            bundleID: $0.owningApplication?.bundleIdentifier ?? "",
                            title: $0.title ?? "", frame: $0.frame)
        }
        guard let chosen = LiveGeometry.pickWindow(for: setup.source, among: candidates) else {
            return nil
        }
        return windows.first { $0.windowID == chosen.windowID }
    }

    static func size(_ configuration: SCStreamConfiguration, for frame: CGRect, scale: CGFloat) {
        configuration.width = max(2, Int(frame.width * scale))
        configuration.height = max(2, Int(frame.height * scale))
    }
}

/// Un stream vivo y su vigilancia: cada segundo comprueba que la ventana
/// sigue ahí y con el mismo tamaño, y si dejaron de llegar fotogramas.
private actor StreamRunner {
    private let setup: LiveSetup
    private let continuation: AsyncStream<LiveFrameEvent>.Continuation
    private var stream: SCStream?
    private var output: FrameOutput?
    private var windowID: CGWindowID?
    private var windowFrame: CGRect?
    private var paused: LivePauseReason?

    init(setup: LiveSetup, continuation: AsyncStream<LiveFrameEvent>.Continuation) {
        self.setup = setup
        self.continuation = continuation
    }

    func run() async {
        await startStream()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            await check()
        }
        try? await stream?.stopCapture()
        continuation.finish()
    }

    private func startStream() async {
        do {
            let (filter, configuration) = try await RegionWatcher.filterAndConfiguration(for: setup)
            let output = FrameOutput(setup: setup, continuation: continuation)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try await stream.startCapture()
            self.stream = stream
            self.output = output
            if case .window = setup.source,
               let window = RegionWatcher.pick(for: setup,
                                               among: try await WindowList.shareableWindows()) {
                windowID = window.windowID
                windowFrame = window.frame
            }
            resume()
        } catch RegionWatcherError.windowNotFound {
            pause(.windowClosed)
        } catch {
            Log.pipeline.error("lectura en vivo: no arrancó el stream: \(error.localizedDescription)")
            pause(.windowClosed)
        }
    }

    private func check() async {
        if case .window = setup.source {
            let windows = (try? await WindowList.shareableWindows()) ?? []
            if let windowID, let window = windows.first(where: { $0.windowID == windowID }) {
                if window.frame.size != windowFrame?.size, let stream {
                    windowFrame = window.frame
                    let configuration = SCStreamConfiguration()
                    configuration.minimumFrameInterval = RegionWatcher.frameInterval
                    configuration.showsCursor = false
                    let scale = CGFloat(SCContentFilter(desktopIndependentWindow: window).pointPixelScale)
                    RegionWatcher.size(configuration, for: window.frame, scale: scale)
                    try? await stream.updateConfiguration(configuration)
                }
            } else {
                // Se cerró: hasta que vuelva a aparecer una de esa app.
                try? await stream?.stopCapture()
                stream = nil
                output = nil
                windowID = nil
                if RegionWatcher.pick(for: setup, among: windows) != nil {
                    await startStream()
                } else {
                    pause(.windowClosed)
                }
                return
            }
        }
        guard let output else { return }
        if output.secondsSinceLastFrame > RegionWatcher.silenceLimit {
            pause(.windowHidden)
        } else {
            resume()
        }
    }

    private func pause(_ reason: LivePauseReason) {
        guard paused != reason else { return }
        paused = reason
        continuation.yield(.paused(reason))
    }

    private func resume() {
        guard paused != nil else { return }
        paused = nil
        continuation.yield(.resumed)
    }
}

/// Recibe los fotogramas en la cola de ScreenCaptureKit.
///
/// ScreenCaptureKit solo manda un fotograma `.complete` cuando algo cambia; si
/// el diálogo se quedó quieto, manda `.idle`. Se repite entonces la última
/// imagen, para que el detector vea el texto dos veces y lo dé por asentado.
private final class FrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.schoolaid.Parla.lectura-en-vivo")
    private let setup: LiveSetup
    private let continuation: AsyncStream<LiveFrameEvent>.Continuation
    private let lock = NSLock()
    private var lastFrameAt = Date()
    /// Solo se toca desde `queue`.
    private var lastImage: CGImage?

    init(setup: LiveSetup, continuation: AsyncStream<LiveFrameEvent>.Continuation) {
        self.setup = setup
        self.continuation = continuation
    }

    var secondsSinceLastFrame: TimeInterval {
        lock.withLock { Date().timeIntervalSince(lastFrameAt) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return }
        switch status {
        case .complete:
            guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
            guard let image, let cropped = RegionWatcher.crop(image, setup: setup) else { return }
            lastImage = cropped
            lock.withLock { lastFrameAt = Date() }
            continuation.yield(.frame(cropped))
        case .idle:
            lock.withLock { lastFrameAt = Date() }
            if let lastImage { continuation.yield(.frame(lastImage)) }
        default:
            break
        }
    }
}
