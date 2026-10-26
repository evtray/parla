import SwiftUI
import ParlaCore

/// Un pendiente con su arreglo. La misma fila en el panel, el menú emergente,
/// Estudio y la bienvenida.
struct SetupIssueRow: View {
    let issue: SetupIssue
    let setup: SetupMonitor
    /// La clave se escribe en Ajustes de Estudio: quien muestra la fila sabe
    /// cómo llegar.
    let onEnterKey: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: issue.item.symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.item.title)
                    .font(.callout.weight(.medium))
                Text(issue.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let title = issue.fix.buttonTitle {
                        Button(title, action: act)
                    }
                    if issue.fix == .openScreenRecordingSettingsOrRelaunch {
                        Button("Reabrir Parla") { setup.relaunch() }
                    }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func act() {
        if issue.fix == .enterAPIKey {
            onEnterKey()
        } else {
            Task { await setup.perform(issue.fix) }
        }
    }
}
