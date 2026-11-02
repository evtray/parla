import AppKit
import Observation
import SwiftData
import SwiftUI
import ParlaCore

/// La lectura en vivo de punta a punta: el flujo de ⌃⌥L, la sesión y dónde se
/// ve la traducción (A, B o C). Aparte de `AppState`, que ya lleva la voz, la
/// captura y los subtítulos.
@MainActor @Observable
final class LiveReadingController {
    private(set) var session: LiveSession?
    /// Para el panel: la ventana o «Un recuadro de la pantalla».
    private(set) var sourceName = ""
    private(set) var notebookName = "Sin cuaderno"

    /// Vale para la siguiente sesión.
    var model: ClaudeModel = Preferences.shared.liveModel {
        didSet { Preferences.shared.liveModel = model }
    }

    /// Se aplica en el acto si hay una sesión en marcha.
    var display: LiveDisplay = Preferences.shared.liveDisplay {
        didSet {
            Preferences.shared.liveDisplay = display
            if session != nil { showViews() }
        }
    }

    @ObservationIgnored let notebooks = NotebookStore(modelContainer: Persistence.container)
    /// La de la sesión en marcha; `begin` la pone.
    @ObservationIgnored var apiKey: String?
    @ObservationIgnored private var panel: FloatingPanel?
    @ObservationIgnored private var overlay: LiveOverlayPanel?
    @ObservationIgnored private var setupWindow: NSWindow?
    @ObservationIgnored private var tracker: Task<Void, Never>?

    /// Arranca con lo recordado si se puede; si no, abre el flujo. `fresh`
    /// pregunta todo otra vez («Cambiar»).
    func begin(apiKey: String, fresh: Bool = false) async {
        self.apiKey = apiKey
        let windows = (try? await WindowList.candidates()) ?? []
        let memory = Preferences.shared.liveSetupMemory
        let flow = fresh ? LiveSetupFlowModel.fresh(memory: memory)
                         : LiveSetupFlowModel(memory: memory, windows: windows)
        if flow.nextStep == nil, let setup = flow.setup {
            start(setup)
        } else {
            showSetupFlow(flow, windows: windows)
        }
    }

    func stop() {
        session?.stop()
        session = nil
        tracker?.cancel()
        tracker = nil
        panel?.orderOut(nil)
        panel = nil
        overlay?.orderOut(nil)
        overlay = nil
        closeSetupFlow()
    }

    /// «Cambiar»: termina la sesión y vuelve a preguntar.
    func reconfigure() {
        guard let apiKey else { return }
        stop()
        Task { await begin(apiKey: apiKey, fresh: true) }
    }

    func showPanel() {
        guard let session else { return }
        if panel == nil {
            panel = FloatingPanel(autosaveName: "ParlaLivePanel") {
                LivePanelView(controller: self, session: session)
            }
        }
        panel?.orderFrontRegardless()
    }

    // MARK: - Sesión

    func start(_ setup: LiveSetup) {
        guard let apiKey else { return }
        // Un ⌃⌥L doble no deja una sesión huérfana leyendo sin panel.
        if session != nil { stop() }
        closeSetupFlow()
        var memory = Preferences.shared.liveSetupMemory
        memory.remember(setup)
        Preferences.shared.liveSetupMemory = memory

        let session = LiveSession(
            setup: setup, rhythm: Preferences.shared.liveRhythm,
            frames: RegionWatcher(setup: setup),
            read: { try await TextReader.read($0) },
            translator: ClaudeExplainer(builder: model.requestBuilder, apiKey: apiKey),
            store: notebooks)
        self.session = session
        session.start()
        Log.pipeline.info("lectura en vivo: encendida")
        Task { await loadNames(for: setup) }
        showViews()
    }

    private func loadNames(for setup: LiveSetup) async {
        switch setup.source {
        case .screen:
            sourceName = "Un recuadro de la pantalla"
        case .window(let bundleID, let title):
            let app = Self.appName(for: bundleID)
            sourceName = title.isEmpty ? app : "\(app) — \(title)"
        }
        guard let id = setup.notebookID else {
            notebookName = "Sin cuaderno"
            return
        }
        let context = ModelContext(Persistence.container)
        notebookName = (try? context.fetch(FetchDescriptor<Notebook>(
            predicate: #Predicate { $0.id == id })))?.first?.name ?? "Sin cuaderno"
    }

    static func appName(for bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path)
                .replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    // MARK: - Vistas A, B y C

    /// B es el panel. A y C van pegadas al recuadro y lo siguen si la ventana
    /// se mueve; con ellas, el panel se abre desde la casilla del menú.
    private func showViews() {
        guard let session else { return }
        overlay?.orderOut(nil)
        overlay = nil
        tracker?.cancel()
        tracker = nil
        switch display {
        case .panel:
            showPanel()
        case .subtitle, .cover:
            panel?.orderOut(nil)
            panel = nil
            let overlay = LiveOverlayPanel(style: display == .cover ? .cover : .strip,
                                           session: session,
                                           followsSpaces: session.setup.source == .screen)
            self.overlay = overlay
            tracker = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.placeOverlay()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func placeOverlay() async {
        guard let session, let overlay else { return }
        guard let (region, onScreen) = await Self.regionOnScreen(for: session.setup),
              Self.showsOverlay(state: session.state, windowOnScreen: onScreen)
        else {
            overlay.orderOut(nil)
            return
        }
        overlay.place(over: region)
        overlay.orderFrontRegardless()
    }

    /// Dónde está el recuadro ahora, en coordenadas de AppKit, y si su ventana
    /// se ve (no minimizada ni en otro escritorio).
    static func regionOnScreen(for setup: LiveSetup) async -> (CGRect, Bool)? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        switch setup.source {
        case .screen:
            return (ScreenCapturer.displaySpace(setup.region, primaryHeight: primaryHeight), true)
        case .window:
            let windows = (try? await WindowList.shareableWindows()) ?? []
            guard let window = RegionWatcher.pick(for: setup, among: windows) else { return nil }
            let frame = window.frame
            let region = CGRect(x: frame.minX + setup.region.minX * frame.width,
                                y: frame.minY + setup.region.minY * frame.height,
                                width: setup.region.width * frame.width,
                                height: setup.region.height * frame.height)
            // La conversión entre los dos sistemas es su propia inversa.
            return (ScreenCapturer.displaySpace(region, primaryHeight: primaryHeight),
                    window.isOnScreen)
        }
    }

    /// A y C tapan lo que haya debajo: solo mientras se lee y la ventana se ve.
    /// Si el usuario cambia de app o de escritorio, no se quedan flotando.
    static func showsOverlay(state: LiveSessionState, windowOnScreen: Bool) -> Bool {
        state == .running && windowOnScreen
    }

    // MARK: - Flujo de configuración

    private func showSetupFlow(_ flow: LiveSetupFlowModel, windows: [WindowCandidate]) {
        closeSetupFlow()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Lectura en vivo"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LiveSetupFlow(
            controller: self, flow: flow, windows: windows)
            .modelContainer(Persistence.container))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        setupWindow = window
    }

    func closeSetupFlow() {
        setupWindow?.orderOut(nil)
        setupWindow = nil
    }

    /// Esconde el flujo mientras se arrastra el recuadro. Con una ventana, el
    /// recuadro se recorta a ella y se guarda como fracción.
    func pickRegion(for source: LiveSource, windows: [WindowCandidate]) async -> CGRect? {
        setupWindow?.orderOut(nil)
        defer {
            NSApp.activate(ignoringOtherApps: true)
            setupWindow?.makeKeyAndOrderFront(nil)
        }
        if case .window(let bundleID, _) = source {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?
                .activate()
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard let selected = await SelectionOverlay.selectRegion() else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let region = ScreenCapturer.displaySpace(selected, primaryHeight: primaryHeight)
        switch source {
        case .screen:
            return region
        case .window:
            // La lista se pide otra vez: la ventana pudo moverse mientras tanto.
            let current = (try? await WindowList.candidates()) ?? windows
            guard let window = LiveGeometry.pickWindow(for: source, among: current) else {
                return nil
            }
            let clipped = region.intersection(window.frame)
            guard !clipped.isNull, clipped.width >= 4, clipped.height >= 4 else { return nil }
            return LiveGeometry.fraction(of: clipped, in: window.frame)
        }
    }
}

extension LiveDisplay {
    var label: String {
        switch self {
        case .subtitle: "Subtítulo encima del recuadro"
        case .panel: "Panel"
        case .cover: "Tapar el recuadro con la traducción"
        }
    }
}

extension LivePauseReason {
    var message: String {
        switch self {
        case .windowHidden: "La ventana está oculta o minimizada"
        case .windowClosed: "La ventana se cerró"
        case .fullScreenUnavailable: "Parla no puede ver la ventana en pantalla completa"
        case .readerFailed: "No se pudo leer el texto del recuadro"
        }
    }
}
