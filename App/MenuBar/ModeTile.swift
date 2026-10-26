import SwiftUI
import ParlaCore

/// Lo que enseña cada botón de modo, fuera de la vista para probarlo.
struct ModeTileModel: Equatable {
    let mode: ParlaMode
    let isActive: Bool
    let shortcut: String?

    var title: String {
        switch mode {
        case .voice: "Voz"
        case .capture: "Captura"
        case .subtitles: "Subtítulos"
        }
    }

    var symbol: String {
        switch mode {
        case .voice: isActive ? "mic.fill" : "mic"
        case .capture: "crop"
        case .subtitles: isActive ? "captions.bubble.fill" : "captions.bubble"
        }
    }

    /// Encendido, el estado; apagado, el atajo para encenderlo sin abrir esto.
    var caption: String {
        if isActive { return mode == .voice ? "Escuchando" : "Activos" }
        return shortcut ?? "Sin atajo"
    }
}

struct ModeTile: View {
    let model: ModeTileModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: model.symbol).font(.title2)
                Text(model.title).font(.callout.weight(.medium))
                Text(model.caption)
                    .font(.caption2)
                    .foregroundStyle(model.isActive ? Theme.onAccent : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(model.isActive ? Theme.onAccent : Color.primary)
            .background(model.isActive ? Theme.accent : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.title), \(model.caption)")
    }
}
