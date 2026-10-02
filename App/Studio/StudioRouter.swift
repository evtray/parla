import Observation

enum StudioSection: Hashable, CaseIterable {
    case history, settings

    var title: String {
        switch self {
        case .history: "Historial"
        case .settings: "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}

/// Qué sección de Estudio se ve. Fuera de la vista para que el menú emergente,
/// el panel y ⌘, puedan abrir Estudio donde toca.
@MainActor
@Observable
final class StudioRouter {
    var section: StudioSection = .history

    /// `nil` deja la sección que estuviera: reabrir Estudio no te saca de donde
    /// estabas.
    func open(_ section: StudioSection?) {
        if let section { self.section = section }
    }
}
