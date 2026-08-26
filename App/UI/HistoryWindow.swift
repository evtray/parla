import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \StoredCard.createdAt, order: .reverse) private var cards: [StoredCard]
    @State private var search = ""

    private var filtered: [StoredCard] {
        guard !search.isEmpty else { return cards }
        return cards.filter {
            $0.spanish.localizedStandardContains(search)
                || $0.english.localizedStandardContains(search)
        }
    }

    var body: some View {
        List(filtered) { card in
            VStack(alignment: .leading, spacing: 6) {
                Text("«\(card.spanish)»").font(.caption).foregroundStyle(.secondary)
                Text(card.english).font(.headline)
                ForEach(Array(card.why.enumerated()), id: \.offset) { _, line in
                    Text("• \(line)").font(.callout)
                }
                if !card.vocab.isEmpty {
                    Text(card.vocab.map(\.term).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 4)
        }
        .searchable(text: $search, prompt: "Buscar en tus frases")
        .frame(minWidth: 520, minHeight: 420)
    }
}
