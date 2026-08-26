import SwiftUI
import ParlaCore

struct CardView: View {
    let presentation: CardPresentation
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("«\(presentation.utterance.text)»")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch presentation.state {
            case .pending:            skeleton
            case .ready(let card):    ready(card)
            case .failed(let error):  failed(error)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).frame(height: 22)
            RoundedRectangle(cornerRadius: 4).frame(height: 12).padding(.trailing, 60)
        }
        .foregroundStyle(.quaternary)
        .redacted(reason: .placeholder)
    }

    private func ready(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.english)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(card.why.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !card.vocab.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(card.vocab.enumerated()), id: \.offset) { _, term in
                        Text(term.term)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .help(term.meaning)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failed(_ error: ExplainerError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.readableMessage).font(.callout).foregroundStyle(.secondary)
            if error.allowsRetry {
                Button("Reintentar", action: onRetry).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
