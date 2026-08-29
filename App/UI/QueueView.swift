import SwiftUI
import ParlaCore

/// Lo que se ha oído y todavía no se ha mandado. Es la única forma de saber
/// que la app te está escuchando cuando no salen tarjetas.
struct QueueView: View {
    let utterances: [Utterance]
    let total: Int
    let isSending: Bool
    let error: String?
    let onSend: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(total == 1 ? "1 frase en cola" : "\(total) frases en cola")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(utterances) { utterance in
                    Text("• \(utterance.text)")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
                if total > utterances.count {
                    Text("y \(total - utterances.count) más")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(action: onSend) {
                    if isSending {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Traduciendo…")
                        }
                    } else {
                        Text("Traducir (\(total))")
                    }
                }
                .disabled(isSending)

                Button("Descartar", action: onDiscard)
                    .disabled(isSending)
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Los patrones del lote entero. Va arriba de las tarjetas porque es lo que
/// no se puede ver mirándolas de una en una.
struct SummaryView: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Patrones de esta sesión", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
