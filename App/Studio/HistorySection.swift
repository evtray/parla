import AppKit
import SwiftUI
import SwiftData
import ParlaCore

struct HistorySection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredCard.createdAt, order: .reverse) private var cards: [StoredCard]
    @State private var search = ""
    @State private var filter: HistoryFilter = .all
    @State private var favoritesOnly = false
    @State private var pendingDeletion: StoredCard?

    private var filtered: [StoredCard] {
        let visible = cards.filter {
            filter.includes(origin: $0.origin, isFavorite: $0.isFavorite, favoritesOnly: favoritesOnly)
        }
        guard !search.isEmpty else { return visible }
        return visible.filter {
            $0.source.localizedStandardContains(search)
                || $0.result.localizedStandardContains(search)
        }
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    "Tus frases aparecerán aquí",
                    systemImage: "character.bubble",
                    description: Text("Cada traducción, captura o subtítulo se guarda en el historial."))
            } else if filtered.isEmpty, !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if filtered.isEmpty {
                ContentUnavailableView("Nada con este filtro",
                                       systemImage: "line.3.horizontal.decrease.circle")
            } else {
                List(filtered) { card in
                    HistoryRow(card: card) { toggleFavorite(card) }
                        .contextMenu {
                            Button("Copiar el inglés") { copyEnglish(card) }
                            Divider()
                            Button("Borrar…", role: .destructive) { pendingDeletion = card }
                        }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar en tus frases")
        .toolbar {
            ToolbarItemGroup {
                Picker("Mostrar", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $favoritesOnly) {
                    Label("Solo favoritas", systemImage: favoritesOnly ? "star.fill" : "star")
                }
                .help("Solo favoritas")
            }
        }
        .confirmationDialog("¿Borrar esta frase?",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            presenting: pendingDeletion) { card in
            Button("Borrar", role: .destructive) { delete(card) }
        } message: { _ in
            Text("No se puede deshacer.")
        }
    }

    private func toggleFavorite(_ card: StoredCard) {
        card.isFavorite.toggle()
        try? context.save()
    }

    private func delete(_ card: StoredCard) {
        context.delete(card)
        try? context.save()
        pendingDeletion = nil
    }

    private func copyEnglish(_ card: StoredCard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.englishText, forType: .string)
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

    /// El filtro de modo y el de favoritas se combinan.
    func includes(origin: String, isFavorite: Bool, favoritesOnly: Bool) -> Bool {
        includes(origin: origin) && (!favoritesOnly || isFavorite)
    }
}
