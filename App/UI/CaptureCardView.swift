import SwiftUI
import ParlaCore

struct CaptureCardView: View {
    let presentation: CardPresentation
    let onRetry: () -> Void
    let onReclassify: (CaptureKind) -> Void

    @State private var sourceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch presentation.state {
            case .pending:
                header(presentation.forcedKind?.label ?? "📷 Leyendo…")
                CardSkeleton()
            case .readyCapture(let card) where card.kind == .skip:
                Text("📷 No encontré texto en la captura.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .readyCapture(let card):
                ready(card)
            case .failed(let error):
                header("📷 Captura")
                failed(error)
            case .ready:
                // Una captura nunca recibe una tarjeta de voz.
                EmptyView()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func ready(_ card: CaptureCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(card.kind.label)

            Text("«\(card.source)»")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(sourceExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { sourceExpanded.toggle() }

            Text(card.result)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if card.kind == .correct && card.why.isEmpty {
                Label("Nada que corregir", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                WhyList(lines: card.why)
            }

            if !card.vocab.isEmpty { VocabChips(vocab: card.vocab) }

            Menu("¿No era eso?") {
                ForEach(CaptureKind.allCases.filter { $0 != .skip && $0 != card.kind },
                        id: \.self) { kind in
                    Button(kind.menuLabel) { onReclassify(kind) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func failed(_ error: ExplainerError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error == .refused ? "No se pudo leer esta captura." : error.readableMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
            if error.allowsRetry {
                Button("Reintentar", action: onRetry).controlSize(.small)
            }
        }
    }
}
