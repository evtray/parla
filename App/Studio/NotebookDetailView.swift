import SwiftData
import SwiftUI

/// Un cuaderno: su nombre y su «De qué trata», editables, y las líneas
/// guardadas con su contexto.
struct NotebookDetailView: View {
    let entry: NotebookListEntry
    let store: NotebookStore
    let onDelete: () -> Void

    @Query private var notebooks: [Notebook]
    @State private var name = ""
    @State private var about = ""
    @State private var showsAll = false
    @State private var confirmsDelete = false

    private var notebookID: UUID? {
        if case .notebook(let id) = entry { id } else { nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notebookID {
                TextField("Nombre", text: $name)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit(commit)
                TextField("De qué trata", text: $about, axis: .vertical)
                    .lineLimit(1...4)
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
                    .onSubmit(commit)
                    .onAppear { load(notebookID) }
            } else {
                Text("Sin cuaderno").font(.title2.weight(.semibold))
                Text("Lo que se leyó sin elegir cuaderno.").foregroundStyle(.secondary)
            }
            HStack {
                Toggle("Ver todas las líneas", isOn: $showsAll).toggleStyle(.switch)
                Spacer()
                if notebookID != nil {
                    Button("Borrar cuaderno", role: .destructive) { confirmsDelete = true }
                }
            }
            .font(.callout)
            Divider()
            NotebookLinesList(notebookID: notebookID, showsAll: showsAll, store: store)
        }
        .padding(20)
        .onDisappear(perform: commit)
        .confirmationDialog("¿Borrar «\(name)» y todas sus líneas?", isPresented: $confirmsDelete) {
            Button("Borrar", role: .destructive) {
                guard let notebookID else { return }
                Task { await store.deleteNotebook(notebookID) }
                onDelete()
            }
        }
    }

    private func load(_ id: UUID) {
        guard let notebook = notebooks.first(where: { $0.id == id }) else { return }
        name = notebook.name
        about = notebook.about
    }

    private func commit() {
        guard let notebookID else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await store.updateNotebook(notebookID, name: name, about: about) }
    }
}

/// Las líneas de un cuaderno, de la más reciente a la más vieja. Guardadas,
/// con explicaciones; todas, solo el inglés y el español.
private struct NotebookLinesList: View {
    let showsAll: Bool
    let store: NotebookStore
    @Query private var lines: [NotebookLine]

    init(notebookID: UUID?, showsAll: Bool, store: NotebookStore) {
        self.showsAll = showsAll
        self.store = store
        let filter: Predicate<NotebookLine>
        switch (notebookID, showsAll) {
        case (let id?, false): filter = #Predicate { $0.notebook?.id == id && $0.isSaved }
        case (let id?, true): filter = #Predicate { $0.notebook?.id == id }
        case (nil, false): filter = #Predicate { $0.notebook == nil && $0.isSaved }
        case (nil, true): filter = #Predicate { $0.notebook == nil }
        }
        _lines = Query(filter: filter, sort: \.readAt, order: .reverse)
    }

    var body: some View {
        if lines.isEmpty {
            Text(showsAll ? "Todavía no hay líneas." : "Todavía no hay líneas guardadas.")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List(lines) { line in
                if showsAll {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.english).font(.system(.body, design: .serif))
                        Text(line.spanish ?? "sin traducir").foregroundStyle(.secondary)
                    }
                } else {
                    SavedLineRow(line: line, store: store)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct SavedLineRow: View {
    let line: NotebookLine
    let store: NotebookStore
    @State private var before: String?
    @State private var after: String?

    private var highlighted: AttributedString {
        var text = AttributedString(line.english)
        for range in ExpressionHighlight.ranges(of: line.expressions.map(\.phrase), in: line.english) {
            guard let attributed = Range(range, in: text) else { continue }
            text[attributed].underlineStyle = .single
            text[attributed].foregroundColor = Theme.accent
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let before { Text(before).font(.caption).foregroundStyle(.tertiary) }
            Text(highlighted).font(.system(.title3, design: .serif)).textSelection(.enabled)
            if let after { Text(after).font(.caption).foregroundStyle(.tertiary) }
            if let spanish = line.spanish { Text(spanish) }
            ForEach(line.expressions, id: \.phrase) { expression in
                Text("\(Text(expression.phrase).bold()): \(expression.meaning)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Quitar") { Task { await store.unsave(line: line.id) } }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
        .task {
            let neighbors = await store.neighbors(ofLine: line.id)
            before = neighbors.before
            after = neighbors.after
        }
    }
}
