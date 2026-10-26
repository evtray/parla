import SwiftUI
import ParlaCore

/// Lo que falta, encima del contenido de Estudio. No aparece si no falta nada.
struct SetupBanner: View {
    let setup: SetupMonitor
    let onEnterKey: () -> Void

    var body: some View {
        if !setup.status.isComplete {
            VStack(alignment: .leading, spacing: 10) {
                Text(setup.status.issues.count == 1
                     ? "Falta una cosa para usar todos los modos"
                     : "Faltan \(setup.status.issues.count) cosas para usar todos los modos")
                    .font(.callout.weight(.semibold))
                ForEach(setup.status.issues) { issue in
                    SetupIssueRow(issue: issue, setup: setup, onEnterKey: onEnterKey)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.08))
            Divider()
        }
    }
}
