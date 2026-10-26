import SwiftUI

/// Un error de la sesión, con «Descartar». El texto ya es legible: nunca es la
/// descripción en bruto de un error.
struct RuntimeNoticeRow: View {
    let notice: RuntimeNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .frame(width: 18)
            Text(notice.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Descartar", action: onDismiss)
                .controlSize(.small)
        }
    }
}
