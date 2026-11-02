import CoreGraphics
import Foundation
import ParlaCore

/// Los pasos de ⌃⌥L antes de leer: de dónde, qué recuadro y en qué cuaderno.
/// Fuera de la vista, para probar cuándo se salta cada uno.
struct LiveSetupFlowModel {
    enum Step: Equatable { case source, region, notebook }

    private(set) var source: LiveSource?
    private(set) var region: CGRect?
    private(set) var notebookID: UUID?
    private var notebookChosen = false
    /// «Cambiar»: el recuadro se marca otra vez aunque la app ya tenga uno.
    private var redrawsRegion = false
    private let memory: LiveSetupMemory

    /// Si lo último que se usó se puede reencontrar, se arranca sin preguntar.
    init(memory: LiveSetupMemory, windows: [WindowCandidate]) {
        self.memory = memory
        guard let last = memory.last else { return }
        let available = switch last.source {
        case .screen: true
        case .window: LiveGeometry.pickWindow(for: last.source, among: windows) != nil
        }
        guard available else { return }
        source = last.source
        region = last.region
        notebookID = last.notebookID
        notebookChosen = true
    }

    /// Empieza de cero aunque haya algo recordado («Cambiar»).
    static func fresh(memory: LiveSetupMemory) -> LiveSetupFlowModel {
        var flow = LiveSetupFlowModel(memory: LiveSetupMemory(byApp: memory.byApp), windows: [])
        flow.redrawsRegion = true
        return flow
    }

    var nextStep: Step? {
        if source == nil { return .source }
        if region == nil { return .region }
        if !notebookChosen { return .notebook }
        return nil
    }

    var setup: LiveSetup? {
        guard let source, let region else { return nil }
        return LiveSetup(source: source, region: region, notebookID: notebookID)
    }

    /// Una app ya usada trae su recuadro y su cuaderno: solo se confirma el
    /// cuaderno. Con «Cambiar», el recuadro se vuelve a marcar.
    mutating func choose(window: WindowCandidate) {
        source = .window(bundleID: window.bundleID, title: window.title)
        let known = memory.byApp[window.bundleID]
        region = redrawsRegion ? nil : known?.region
        notebookID = known?.notebookID
    }

    mutating func chooseScreen() {
        source = .screen
        region = nil
    }

    mutating func chooseRegion(_ region: CGRect) {
        self.region = region
    }

    mutating func chooseNotebook(_ id: UUID?) {
        notebookID = id
        notebookChosen = true
    }
}
