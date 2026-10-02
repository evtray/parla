import SwiftUI
import SwiftData
import ParlaCore

struct HistoryView: View {
    @Query(sort: \StoredCard.createdAt, order: .reverse) private var cards: [StoredCard]
    @State private var search = ""

    private var filtered: [StoredCard] {
        guard !search.isEmpty else { return cards }
        return cards.filter {
            $0.source.localizedStandardContains(search)
                || $0.result.localizedStandardContains(search)
        }
    }

    var body: some View {
        List(filtered) { card in
            VStack(alignment: .leading, spacing: 6) {
                if let kind = card.kind.flatMap(CaptureKind.init(rawValue:)) {
                    Text(kind.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("«\(card.source)»").font(.caption).foregroundStyle(.secondary)
                Text(card.result).font(.headline)
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
