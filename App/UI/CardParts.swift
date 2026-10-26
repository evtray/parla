import SwiftUI
import ParlaCore

/// Lo que se ve mientras llega la respuesta.
struct CardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).frame(height: 22)
            RoundedRectangle(cornerRadius: 4).frame(height: 12).padding(.trailing, 60)
        }
        .foregroundStyle(.quaternary)
        .redacted(reason: .placeholder)
    }
}

/// El porqué, en viñetas.
struct WhyList: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// El vocabulario. En filas que saltan de línea: una captura larga trae hasta
/// cinco términos y no caben en una fila del panel.
struct VocabChips: View {
    let vocab: [VocabTerm]

    var body: some View {
        FlowLayout {
            ForEach(Array(vocab.enumerated()), id: \.offset) { _, term in
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

/// Coloca las vistas en filas y salta de línea cuando la siguiente no cabe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    /// Los índices de cada fila. Una pieza más ancha que la fila va sola: un
    /// chip no se puede partir.
    static func rows(for widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let needed = current.isEmpty ? width : used + spacing + width
            if needed > maxWidth, !current.isEmpty {
                rows.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(for: sizes.map(\.width),
                             maxWidth: proposal.width ?? .infinity, spacing: spacing)
        let widest: CGFloat = rows.map { width(of: $0, sizes) }.max() ?? 0
        let gaps: CGFloat = spacing * CGFloat(max(rows.count - 1, 0))
        let tallest: CGFloat = rows.reduce(0) { $0 + height(of: $1, sizes) }
        return CGSize(width: widest, height: tallest + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in Self.rows(for: sizes.map(\.width), maxWidth: bounds.width, spacing: spacing) {
            var x = bounds.minX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += height(of: row, sizes) + spacing
        }
    }

    // Partidas en funciones: en una sola expresión, el compilador no termina
    // de inferir los tipos.
    private func width(of row: [Int], _ sizes: [CGSize]) -> CGFloat {
        let content: CGFloat = row.reduce(0) { $0 + sizes[$1].width }
        return content + spacing * CGFloat(row.count - 1)
    }

    private func height(of row: [Int], _ sizes: [CGSize]) -> CGFloat {
        row.reduce(0) { max($0, sizes[$1].height) }
    }
}
