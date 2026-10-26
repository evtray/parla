import SwiftUI

struct HistoryRow: View {
    let card: StoredCard
    let onToggleFavorite: () -> Void

    private var side: EnglishSide { card.englishSide }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: CardOriginStyle.symbol(origin: card.origin))
                    Text(CardOriginStyle.name(origin: card.origin, kind: card.kind))
                    Text(card.createdAt, format: .dateTime.day().month().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(card.source)
                    .font(side.sourceIsEnglish ? Theme.english(.body) : .callout)
                    .foregroundStyle(.secondary)
                Text(card.result.isEmpty ? "(sin traducción)" : card.result)
                    .font(side.resultIsEnglish ? Theme.english(.title3) : .headline)

                ForEach(Array(card.why.enumerated()), id: \.offset) { _, line in
                    Text("• \(line)").font(.callout)
                }
                if !card.vocab.isEmpty {
                    Text(card.vocab.map(\.term).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
            Button(action: onToggleFavorite) {
                Image(systemName: card.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(card.isFavorite ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .help(card.isFavorite ? "Quitar de favoritas" : "Marcar como favorita")
        }
        .padding(.vertical, 6)
    }
}
