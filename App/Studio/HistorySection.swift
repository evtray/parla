import SwiftUI
import SwiftData
import ParlaCore

struct HistorySection: View {
    @Query(sort: \StoredCard.createdAt, order: .reverse) private var cards: [StoredCard]
    @State private var search = ""
    @State private var filter: HistoryFilter = .all

    private var filtered: [StoredCard] {
        let byOrigin = cards.filter { filter.includes(origin: $0.origin) }
        guard !search.isEmpty else { return byOrigin }
        return byOrigin.filter {
            $0.source.localizedStandardContains(search)
                || $0.result.localizedStandardContains(search)
        }
    }

    var body: some View {
        List(filtered) { card in
            VStack(alignment: .leading, spacing: 6) {
                if card.origin == "system" {
                    Text("🎧 Subtítulos").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                } else if let kind = card.kind.flatMap(CaptureKind.init(rawValue:)) {
                    Text(kind.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("«\(card.source)»").font(.caption).foregroundStyle(.secondary)
                Text(card.result.isEmpty ? "(sin traducción)" : card.result).font(.headline)
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
        .toolbar {
            Picker("Mostrar", selection: $filter) {
                ForEach(HistoryFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Una hora de video son cientos de frases: sin filtro taparían las tarjetas
/// de voz y de captura.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, voice, screen, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:    "Todo"
        case .voice:  "Voz"
        case .screen: "Capturas"
        case .system: "Subtítulos"
        }
    }

    /// Los valores de `StoredCard.origin` coinciden con los `rawValue`.
    func includes(origin: String) -> Bool {
        self == .all || rawValue == origin
    }
}
