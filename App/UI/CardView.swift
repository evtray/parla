import SwiftUI
import ParlaCore

struct CardView: View {
    let presentation: CardPresentation
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("«\(presentation.utterance?.text ?? "")»")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch presentation.state {
            case .pending:            CardSkeleton()
            case .ready(let card):    ready(card)
            case .failed(let error):  failed(error)
            // Una tarjeta de voz nunca recibe una de captura.
            case .readyCapture:       EmptyView()
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func ready(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.english)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            WhyList(lines: card.why)

            if !card.vocab.isEmpty { VocabChips(vocab: card.vocab) }
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
