import SwiftUI

struct LastPhraseView: View {
    let card: StoredCard
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Última frase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.englishText)
                    .font(Theme.english(.body))
                    .lineLimit(2)
                if !card.otherText.isEmpty {
                    Text(card.otherText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Abrir en Estudio")
    }
}
